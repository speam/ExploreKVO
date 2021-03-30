//
//  ViewController.m
//  OCTest
//
//  Created by IMO on 2020/12/3.
//

#import "ViewController.h"
#import "Person.h"
#import "NSObject+JYKVO.h"

static void *PersonContext = &PersonContext;

@interface ViewController ()

@property (nonatomic) Person *person;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemGrayColor];
    
    self.person = [Person new];
    self.person.name = @"旧名字";
    
    [self.person jy_addObserver:self forKeyPath:@"name" block:^(id  _Nonnull observer, NSString * _Nonnull keyPath, id  _Nonnull oldValue, id  _Nonnull newValue) {
        NSLog(@"旧值：%@", oldValue);
        NSLog(@"新值：%@", newValue);
        NSLog(@"path：%@", keyPath);
    }];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.person.name = @"新名字";
}
@end
