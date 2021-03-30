//
//  NSObject+JYKVO.h
//  OCTest
//
//  Created by IMO on 2021/3/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^JYKVOBlock)(id observer, NSString *keyPath, id oldValue,id newValue);

@interface NSObject (JYKVO)

/// 对属性添加观察
/// @param observer 观察者
/// @param keyPath 观察的属性
/// @param block 属性改变后的回调
- (void)jy_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath block:(JYKVOBlock)block;

@end

NS_ASSUME_NONNULL_END
