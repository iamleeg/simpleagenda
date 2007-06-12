/* emacs buffer mode hint -*- objc -*- */

#import <AppKit/AppKit.h>
#import "LocalStore.h"
#import "AppointmentEditor.h"
#import "StoreManager.h"
#import "AppController.h"
#import "Event.h"
#import "PreferencesController.h"
#import "UserDefaults.h"
#import "defines.h"

NSComparisonResult sortAppointments(Event *a, Event *b, void *data)
{
  return [[a startDate] compare:[b startDate]];
}

@implementation AppController

- (NSDictionary *)defaults
{
  NSDictionary *dict = [NSDictionary 
			 dictionaryWithObjects:[NSArray arrayWithObjects:@"9", @"18", @"15", nil]
			 forKeys:[NSArray arrayWithObjects:FIRST_HOUR, LAST_HOUR, MIN_STEP, nil]];
  return dict;
}

- (id)init
{
  self = [super init];
  if (self) {
    _defaults = [UserDefaults sharedInstance];
    [_defaults setHardDefaults:[self defaults]];
    [_defaults registerClient:self forKey:FIRST_HOUR];
    [_defaults registerClient:self forKey:LAST_HOUR];
    [_defaults registerClient:self forKey:MIN_STEP];
    _editor = [AppointmentEditor new];
    _cache = [[NSMutableSet alloc] initWithCapacity:16];
    _sm = [StoreManager new];
    _pc = [[PreferencesController alloc] initWithStoreManager:_sm];
  }
  return self;
}

/* 
 * FIXME : is there a good reason to 'cache'
 * events in there ? Each store can probably 
 * do it better and only if needed
 */
- (void)updateCache
{
  NSArray *array;
  Date *start = [[calendar date] copy];
  Date *end = [[calendar date] copy];
  NSEnumerator *enumerator;
  id <AgendaStore> store;

  [start setMinute:[self firstHourForDayView] * 60];
  [end setMinute:([self lastHourForDayView] + 1) * 60];

  [_cache removeAllObjects];
  enumerator = [_sm objectEnumerator];
  while ((store = [enumerator nextObject])) {
    array = [store scheduledAppointmentsFrom:start to:end];
    [_cache addObjectsFromArray:array];
  }
  
  [start release];
  [end release];
  [dayView reloadData];
}


- (void)defaultDidChanged:(NSString *)name
{
  [self updateCache];
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
  [self updateCache];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender
{
  [_cache release];
  [_editor release];
  [_pc release];
  [_sm release];
  [_defaults unregisterClient:self];
  [_defaults release];
  return NSTerminateNow;
}

- (void)showPrefPanel:(id)sender
{
  [_pc showPreferences];
}

- (int)_sensibleStartForDuration:(int)duration
{
  int minute = [self firstHourForDayView] * 60;
  NSArray *sorted = [[_cache allObjects] sortedArrayUsingFunction:sortAppointments context:nil];
  NSEnumerator *enumerator = [sorted objectEnumerator];
  Event *apt;

  while ((apt = [enumerator nextObject])) {
    if (minute + duration <= [[apt startDate] minuteOfDay])
      return minute;
    minute = [[apt startDate] minuteOfDay] + [apt duration];
  }
  if (minute < [self lastHourForDayView] * 60)
    return minute;
  return [self firstHourForDayView] * 60;
}

- (void)_editAppointment:(Event *)apt
{
  if ([_editor editAppointment:apt withStoreManager:_sm])
    [self updateCache];
}

- (void)addAppointment:(id)sender
{
  Date *date = [[calendar date] copy];
  [date setMinute:[self _sensibleStartForDuration:60]];
  Event *apt = [[Event alloc] initWithStartDate:date 
					  duration:60
					  title:@"edit title..."];
  if (apt && [_editor editAppointment:apt withStoreManager:_sm])
    [self updateCache];
  [date release];
  [apt release];
}

- (void)editAppointment:(id)sender
{
  Event *apt = [dayView selectedAppointment];

  if (apt)
    [self _editAppointment:apt];
}

- (void)delAppointment:(id)sender
{
  Event *apt = [dayView selectedAppointment];

  if (apt) {
    [[apt store] delAppointment: apt];
    [self updateCache];
  }
}

- (void)copy:(id)sender
{
  _selection = [dayView selectedAppointment];
  _deleteSelection = NO;
}

- (void)cut:(id)sender
{
  _selection = [dayView selectedAppointment];
  _deleteSelection = YES;
}

- (void)paste:(id)sender
{
  if (_selection) {
    Date *date = [[calendar date] copy];
    if (_deleteSelection) {
      [date setMinute:[self _sensibleStartForDuration:[_selection duration]]];
      [_selection setStartDate:date andConstrain:NO];
      [[_selection store] updateAppointment:_selection];
    } else {
      Event *new = [_selection copy];
      [date setMinute:[self _sensibleStartForDuration:[new duration]]];
      [new setStartDate:date andConstrain:NO];
      [[_selection store] addAppointment:new];
      [new release];
    }
    [date release];
    [self updateCache];
  }
}

- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem
{
  SEL action = [menuItem action];
  if (action == @selector(copy:) ||
      action == @selector(cut:) ||
      action == @selector(paste:) ||
      action == @selector(editAppointment:) ||
      action == @selector(delAppointment:)) {
    return [dayView selectedAppointment] != nil;
  }
  return YES;
}


/* CalendarView delegate method */
- (void)dateChanged:(Date *)newDate
{
  [self updateCache];
  NSLog(@"Show data for %@ => %d apt", [newDate description], [_cache count]);
}

/* DayViewDataSource methods */
- (int)firstHourForDayView
{
  return [_defaults integerForKey:FIRST_HOUR];
}

- (int)lastHourForDayView
{
  return [_defaults integerForKey:LAST_HOUR];
}

- (int)minimumStepForDayView
{
  return [_defaults integerForKey:MIN_STEP];
}

- (NSEnumerator *)scheduledAppointmentsForDayView
{
  return [_cache objectEnumerator];
}

/* DayView Delegate methods */

- (void)doubleClickOnAppointment:(Event *)apt
{
  /*
   * FIXME : we should allow to view appointment's 
   * details even if it's read only
   */
  if ([[apt store] isWritable])
    [self _editAppointment:apt];
}

- (void)modifyAppointment:(Event *)apt
{
  [[apt store] updateAppointment:apt];
}

- (void)createAppointmentFrom:(int)start to:(int)end
{
  Date *date = [[calendar date] copy];
  [date setMinute:start];
  Event *apt = [[Event alloc] initWithStartDate:date 
			      duration:end - start 
			      title:@"edit title..."];
  if (apt && [_editor editAppointment:apt withStoreManager:_sm])
    [self updateCache];
  [date release];
  [apt release];
}

@end
