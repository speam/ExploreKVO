//
//  NSObject+JYKVO.m
//  OCTest
//
//  Created by IMO on 2021/3/26.
//

#import "NSObject+JYKVO.h"
#import <objc/message.h>

static NSString *const kJYKVOPrefix = @"JYKVONotifying_";
static NSString *const kJYKVOAssiociateKey = @"kJYKVO_AssiociateKey";

@interface JYKVOInfo : NSObject
@property (nonatomic, weak) NSObject *observer;
@property (nonatomic, copy) NSString *keyPath;
@property (nonatomic, copy) JYKVOBlock handleBlock;
@end

@implementation JYKVOInfo

- (instancetype)initWitObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath handleBlock:(JYKVOBlock)block {
    if (self = [super init]) {
        _observer = observer;
        _keyPath  = keyPath;
        _handleBlock = block;
    }
    return self;
}
@end

@implementation NSObject (JYKVO)

#pragma mark - public
- (void)jy_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath block:(JYKVOBlock)block {
    if (keyPath == nil || keyPath.length == 0) return;
    
    // 判断是否有对应的 setter
    if (![self isContainSetterMethodFromKeyPath:keyPath]) return;
    
    // 判断 automaticallyNotifiesObserversForKey 方法返回的布尔值
    BOOL isAutomatically = [self jy_performSelectorWithMethodName:@"automaticallyNotifiesObserversForKey:" keyPath:keyPath];
    if (!isAutomatically) return;
    
    // 动态生成子类
    Class newClass = [self createChildClassWithKeyPath:keyPath];
    
    // isa指向修改->指向动态子类
    object_setClass(self, newClass);
    
    // 保存信息
    JYKVOInfo *info = [[JYKVOInfo alloc] initWitObserver:observer forKeyPath:keyPath handleBlock:block];
    NSMutableArray *mArray = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)(kJYKVOAssiociateKey));
    if (!mArray) {
        mArray = [NSMutableArray arrayWithCapacity:1];
        objc_setAssociatedObject(self, (__bridge const void * _Nonnull)(kJYKVOAssiociateKey), mArray, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [mArray addObject:info];
}

#pragma mark - private
/// 判断是否存在对应的 setter
/// @param keyPath 属性名
- (BOOL)isContainSetterMethodFromKeyPath:(NSString *)keyPath {
    Class class         = object_getClass(self);
    SEL setterSeletor   = NSSelectorFromString(setterForKeyPath(keyPath));
    Method setterMethod = class_getInstanceMethod(class, setterSeletor);
    if (!setterMethod) {
        NSLog(@"没找到属性:%@的setter方法", keyPath);
        return NO;
    }
    return YES;
}


/// 动态调用类方法并返回是否成功
/// @param methodName 要调用的类方法
/// @param keyPath 参数
- (BOOL)jy_performSelectorWithMethodName:(NSString *)methodName keyPath:(NSString *)keyPath {
    if ([[self class] respondsToSelector: NSSelectorFromString(methodName)]) {
        // 忽略 Xcode 警告 "performSelector may cause a leak because its selector is unknown"（因为performSelector的选择器未知可能会引起泄漏）
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        BOOL b = [[self class] performSelector:NSSelectorFromString(methodName) withObject:keyPath];
        return b;
#pragma clang diagnostic pop
    }
    return NO;
}

// 根据 key 返回相应的 setter 方法的全名
static NSString *setterForKeyPath(NSString *keyPath) {
    if (keyPath.length <= 0) { return nil; }
    NSString *getterStr = keyPath.capitalizedString;
    return [NSString stringWithFormat:@"set%@:",getterStr];
}

// 根据 setter 方法名返回对应的 getter 方法名
static NSString *getterForSetter(NSString *setter) {
    if (setter.length <= 0 || ![setter hasPrefix:@"set"] || ![setter hasSuffix:@":"]) { return nil;}
    NSRange range = NSMakeRange(3, setter.length - 4);
    NSString *getter = [setter substringWithRange:range];
    NSString *firstString = [[getter substringToIndex:1] lowercaseString];
    return  [getter stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:firstString];
}

// 创建动态子类
- (Class)createChildClassWithKeyPath:(NSString *)keyPath {
    // 获取新类的类名
    NSString *oldClassName = NSStringFromClass([self class]);
    NSString *newClassName = [NSString stringWithFormat:@"%@%@", kJYKVOPrefix, oldClassName];
    Class newClass = NSClassFromString(newClassName);
    
    // 防止重复创建新类
    if (newClass) return newClass;
    
    /**
     * 申请类
     * 如果内存中不存在, 创建生成
     * 参数一: 父类
     * 参数二: 新类的名字
     * 参数三: 新类的开辟的额外空间
     */
    newClass = objc_allocateClassPair([self class], newClassName.UTF8String, 0);
    // 注册类
    objc_registerClassPair(newClass);
    
    // 添加 +class 方法
    SEL classSEL = NSSelectorFromString(@"class");
    Method classMethod = class_getInstanceMethod([self class], classSEL);
    const char *classTypes = method_getTypeEncoding(classMethod);
    class_addMethod(newClass, classSEL, (IMP)jy_class, classTypes);
    
    // 添加 setter
    SEL setterSEL = NSSelectorFromString(setterForKeyPath(keyPath));
    Method setterMethod = class_getInstanceMethod([self class], setterSEL);
    const char *setterTypes = method_getTypeEncoding(setterMethod);
    class_addMethod(newClass, setterSEL, (IMP)jy_setter, setterTypes);
    
    // 交换 dealloc 实现
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self JYMethodSwizzlingWithClass:[self class] oriSEL:NSSelectorFromString(@"dealloc") swizzledSEL:@selector(jy_dealloc)];
    });
    
    return newClass;
}

// 当对象销毁的时候会调用 dealloc，在该方法中将 isa 指针重新指向原来的类
- (void)jy_dealloc {
    Class superClass = [self class];
    object_setClass(self, superClass);
    [self jy_dealloc];
}

// + class 方法的实现
Class jy_class(id self, SEL _cmd) {
    return class_getSuperclass(object_getClass(self));
}

// setter 方法的实现
static void jy_setter(id self, SEL _cmd, id newValue) {
    // 1️⃣转发给父类，改变父类的值
    void (*jy_msgSendSuper)(void *, SEL, id) = (void *)objc_msgSendSuper;
    struct objc_super superStruct = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self)),
    };
    jy_msgSendSuper(&superStruct, _cmd, newValue);
    
    // 2️⃣取旧值
    NSString *keyPath = getterForSetter(NSStringFromSelector(_cmd));
    id oldValue = [self valueForKey:keyPath];
    
    // 3️⃣通知观察者
    // 1.拿到观察者，在添加观察者的时候通过关联对象将 observer 存储了起来。
    NSMutableArray *mArray = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)(kJYKVOAssiociateKey));
    
    // 2.消息发送给观察者
    for (JYKVOInfo *info in mArray) {
        if ([info.keyPath isEqualToString:keyPath] && info.handleBlock) {
            info.handleBlock(info.observer, keyPath, oldValue, newValue);
        }
    }
}

// 交换方法的方法
- (void)JYMethodSwizzlingWithClass:(Class)cls oriSEL:(SEL)oriSEL swizzledSEL:(SEL)swizzledSEL {
    
    if (!cls) NSLog(@"传入的交换类不能为空");
    
    Method oriMethod = class_getInstanceMethod(cls, oriSEL);
    Method swiMethod = class_getInstanceMethod(cls, swizzledSEL);
    
    if (!oriMethod) {
        class_addMethod(cls, oriSEL, method_getImplementation(swiMethod), method_getTypeEncoding(swiMethod));
        method_setImplementation(swiMethod, imp_implementationWithBlock(^(id self, SEL _cmd) {
            NSLog(@"方法未实现");
        }));
    }

    BOOL didAddMethod = class_addMethod(cls, oriSEL, method_getImplementation(swiMethod), method_getTypeEncoding(swiMethod));
    if (didAddMethod) {
        class_replaceMethod(cls, swizzledSEL, method_getImplementation(oriMethod), method_getTypeEncoding(oriMethod));
    } else {
        method_exchangeImplementations(oriMethod, swiMethod);
    }
}

@end
