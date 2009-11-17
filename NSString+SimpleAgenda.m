#import <Foundation/Foundation.h>
#import "NSString+SimpleAgenda.h"
#import "config.h"
#ifdef HAVE_UUID_UUID_H
#import <uuid/uuid.h>
#else
#import "Date.h"
#endif

@implementation NSString(SimpleAgenda)
+ (NSString *)uuid
{
#ifdef HAVE_UUID_UUID_H
  uuid_t uuid;
  char uuid_str[37];

  uuid_generate(uuid);
  uuid_unparse(uuid, uuid_str);
  return [NSString stringWithCString:uuid_str];
#else
  Date *now = [Date now];
  static Date *lastDate;
  static int counter;

  if (!lastDate)
    ASSIGNCOPY(lastDate, now);
  else {
    if (![lastDate compareTime:now])
      counter++;
    else {
      ASSIGNCOPY(lastDate, now);
      counter = 0;
    }
  }
  return [NSString stringWithFormat:@"%@-%d-%@", [now description], counter, [[NSHost currentHost] address]];
#endif
}
@end
