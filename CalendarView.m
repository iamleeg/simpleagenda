#import <AppKit/AppKit.h>
#import "Date.h"
#import "CalendarView.h"

@interface DayFormatter : NSFormatter
@end
@implementation DayFormatter
- (NSString *)stringForObjectValue:(id)anObject
{
  NSAssert([anObject isKindOfClass:[Date class]], @"Needs a Date as input");
  return [NSString stringWithFormat:@"%2d", [anObject dayOfMonth]];
}
- (BOOL)getObjectValue:(id *)anObject forString:(NSString *)string errorDescription:(NSString **)error
{
  return NO;
}
- (NSAttributedString *)attributedStringForObjectValue:(id)anObject withDefaultAttributes:(NSDictionary *)attributes
{
  return nil;
}
@end


@implementation CalendarView
static NSImage *_1left;
static NSImage *_2left;
static NSImage *_1right;
static NSImage *_2right;
+ (void)initialize
{
  NSString *path;

  path = [[NSBundle mainBundle] pathForImageResource:@"1left"];
  _1left = [[NSImage alloc] initWithContentsOfFile:path];
  path = [[NSBundle mainBundle] pathForImageResource:@"2left"];
  _2left = [[NSImage alloc] initWithContentsOfFile:path];
  path = [[NSBundle mainBundle] pathForImageResource:@"1right"];
  _1right = [[NSImage alloc] initWithContentsOfFile:path];
  path = [[NSBundle mainBundle] pathForImageResource:@"2right"];
  _2right = [[NSImage alloc] initWithContentsOfFile:path];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  RELEASE(date);
  RELEASE(monthDisplayed);
  [_dayTimer invalidate];
  RELEASE(_dayTimer);
  RELEASE(delegate);
  RELEASE(dataSource);
  [boldFont release];
  [normalFont release];
  [title release];
  [matrix release];
  [obl release];
  [tbl release];
  [obr release];
  [tbr release];
  [super dealloc];
}

- (id)initWithFrame:(NSRect)frame
{
  int i;
  int j;
  int tag;
  Date *now;
  DayFormatter *formatter;

  self = [super initWithFrame:frame];
  if (self) {
    NSArray *days = [[NSUserDefaults standardUserDefaults] objectForKey:NSShortWeekDayNameArray];
    boldFont = RETAIN([NSFont boldSystemFontOfSize:11]);
    normalFont = RETAIN([NSFont systemFontOfSize:11]);
    delegate = nil;
    dataSource = nil;

    title = [[NSTextField alloc] initWithFrame: NSMakeRect(32, 128, 168, 20)];
    [title setEditable:NO];
    [title setDrawsBackground:NO];
    [title setBezeled:NO];
    [title setBordered:NO];
    [title setSelectable:NO];
    [title setFont:normalFont];
    [title setAlignment: NSCenterTextAlignment];
    [self addSubview: title];

    tbl = [[NSButton alloc] initWithFrame:NSMakeRect(9, 128, 12, 20)];
    [tbl setImage:_2left];
    [tbl setBordered:NO];
    [tbl setTarget:self];
    [tbl setAction:@selector(previousYear:)];
    [self addSubview:tbl];
    obl = [[NSButton alloc] initWithFrame:NSMakeRect(22, 128, 12, 20)];
    [obl setImage:_1left];
    [obl setBordered:NO];
    [obl setTarget:self];
    [obl setAction:@selector(previousMonth:)];
    [self addSubview:obl];
    obr = [[NSButton alloc] initWithFrame:NSMakeRect(201, 128, 12, 20)];
    [obr setButtonType:NSMomentaryPushInButton];
    [obr setImage:_1right];
    [obr setBordered:NO];
    [obr setTarget:self];
    [obr setAction:@selector(nextMonth:)];
    [self addSubview:obr];
    tbr = [[NSButton alloc] initWithFrame:NSMakeRect(214, 128, 12, 20)];
    [tbr setImage:_2right];
    [tbr setBordered:NO];
    [tbr setTarget:self];
    [tbr setAction:@selector(nextYear:)];
    [self addSubview:tbr];

    NSTextFieldCell *cell = [NSTextFieldCell new];
    [cell setEditable: NO];
    [cell setSelectable: NO];
    [cell setAlignment: NSRightTextAlignment];
    [cell setFont:normalFont];

    matrix = [[NSMatrix alloc] initWithFrame: NSMakeRect(9, 6, 220, 128)
			       mode: NSListModeMatrix
			       prototype: cell
			       numberOfRows: 7
			       numberOfColumns: 8];
    [matrix setIntercellSpacing: NSZeroSize];
    [matrix setDelegate:self];
    [matrix setAction: @selector(selectDay:)];
    [matrix setDoubleAction: @selector(doubleClick:)];
    
    NSColor *orange = [NSColor orangeColor];
    NSColor *white = [NSColor whiteColor];
    for (i = 0; i < 8; i++) {
      cell = [matrix cellAtRow: 0 column: i];
      [cell setBackgroundColor: orange];
      [cell setTextColor: white];
      [cell setDrawsBackground: YES];
      if (i < 7 && i > 0)
	[cell setStringValue: [[days objectAtIndex: i] substringToIndex:1]];
      else if (i == 7)
	[cell setStringValue: [[days objectAtIndex: 0] substringToIndex:1]];
    }
    for (i = 0; i < 7; i++) {
      cell = [matrix cellAtRow: i column: 0];
      [cell setBackgroundColor: orange];
      [cell setTextColor: white];
      [cell setDrawsBackground: YES];
    }
    formatter = [DayFormatter new];
    for (i = 1, tag = 1; i < 8; i++) {
      for (j = 1; j < 7; j++) {
	[[matrix cellAtRow: j column: i] setFormatter:formatter];
	[[matrix cellAtRow: j column: i] setTag:tag++];
      }
    }
    [formatter release];
    [self addSubview: matrix];

    now = [Date today];
    [self setDate:now];
    [now incrementDay];
    _dayTimer = [[NSTimer alloc] initWithFireDate:[now calendarDate]
				         interval:86400
				           target:self
				         selector:@selector(dayChanged:)
				         userInfo:nil
				          repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_dayTimer forMode:NSDefaultRunLoopMode];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dataChanged:) name:SADataChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dataChanged:) name:SAStatusChangedForStore object:nil];
  }
  return self;
}

- (void)updateTitle
{
  [title setStringValue:[self dateAsString]];
}

- (void)clearSelectedDay
{
  [[matrix cellWithTag:bezeledCell] setBezeled:NO];
}

- (void)setSelectedDay
{
  NSCell *cell;
  int i, j;
  id object;

  for (i = 1; i < 8; i++) {
    for (j = 1; j < 7; j++) {
      cell = [matrix cellAtRow:j column:i];
      object = [cell objectValue];
      if (object != nil && ![date compare:object]) {
	bezeledCell = [cell tag];
	[cell setBezeled:YES];
	[self updateTitle];
	return;
      }
    }
  }
}

- (void)updateView
{
  int row, column, week;
  Date *day, *today;
  NSTextFieldCell *cell;
  NSColor *clear = [NSColor clearColor];
  NSColor *white = [NSColor whiteColor];
  NSColor *black = [NSColor blackColor];

  [self clearSelectedDay];
  today = [Date today];
  day = [monthDisplayed copy];
  [day setDay: 1];
  column = [day weekday];
  [day changeDayBy:1-column];
  for (row = 1; row < 7; row++) {
    week = [day weekOfYear];
    [[matrix cellAtRow:row column:0] setStringValue:[NSString stringWithFormat:@"%d ", week]];
    for (column = 1; column < 8; column++, [day incrementDay]) {
      cell = [matrix cellAtRow: row column: column];
      if ([day compare:today] == 0) {
	[cell setBackgroundColor:[NSColor yellowColor]];
	[cell setDrawsBackground:YES];
      } else {
	[cell setBackgroundColor:clear];
	[cell setDrawsBackground:NO];
      }
      [cell setObjectValue:[day copy]];
      if (dataSource && [[dataSource scheduledAppointmentsForDay:day] count])
	[cell setFont:boldFont];
      else
	[cell setFont: normalFont];
      if ([day monthOfYear] == [monthDisplayed monthOfYear])
	[cell setTextColor:black];
      else
	[cell setTextColor:white];
    }
  }
  [self setSelectedDay];
  [day release];
}

- (void)dayChanged:(NSTimer *)timer
{
  [self updateView];
  if ([delegate respondsToSelector:@selector(calendarView:currentDateChanged:)])
    [delegate calendarView:self currentDateChanged:[Date today]];
}

- (void)previousYear:(id)sender
{
  Date *cdate = AUTORELEASE([date copy]);

  [cdate setYear:[cdate year]-1];
  [self setDate:cdate];
}
- (void)previousMonth:(id)sender
{
  Date *cdate = AUTORELEASE([date copy]);

  [cdate setMonth:[cdate monthOfYear]-1];
  [self setDate:cdate];
}
- (void)nextMonth:(id)sender
{
  Date *cdate = AUTORELEASE([date copy]);

  [cdate setMonth:[cdate monthOfYear]+1];
  [self setDate:cdate];
}
- (void)nextYear:(id)sender
{
  Date *cdate = AUTORELEASE([date copy]);

  [cdate setYear:[cdate year]+1];
  [self setDate:cdate];
}

- (void)selectDay:(id)sender
{
  id day = [[matrix selectedCell] objectValue];

  if ([day isKindOfClass:[Date class]]) {
    [self clearSelectedDay];
    ASSIGNCOPY(date, day);
    [self setSelectedDay];
    if ([delegate respondsToSelector:@selector(calendarView:selectedDateChanged:)])
      [delegate calendarView:self selectedDateChanged:date];
  }
}

- (void)doubleClick:(id)sender
{
  if ([[matrix selectedCell] tag] > 0 && [delegate respondsToSelector:@selector(calendarView:userActionForDate:)])
    [delegate calendarView:self userActionForDate:date];
}

- (void)setDelegate: (id)aDelegate
{
  ASSIGN(delegate, aDelegate);
}
- (id)delegate
{
  return delegate;
}

- (void)setDate:(Date *)nDate
{
  ASSIGNCOPY(date, nDate);
  ASSIGNCOPY(monthDisplayed, nDate);
  [self updateView];
  if ([delegate respondsToSelector:@selector(calendarView:selectedDateChanged:)])
    [delegate calendarView:self selectedDateChanged:date];
}
- (Date *)date
{
  return date;
}

- (NSString *)dateAsString
{
  return [[date calendarDate] descriptionWithCalendarFormat:[[NSUserDefaults standardUserDefaults] objectForKey:NSDateFormatString]];
}

- (void)setDataSource:(NSObject <AgendaDataSource> *)source
{
  ASSIGN(dataSource, source);
  [self updateView];
}
- (id)dataSource
{
  return dataSource;
}

- (void)dataChanged:(NSNotification *)not
{
  [self updateView];
}
@end
