#import "utils.h"

void swizzleClassMethod(Class cls, SEL origSel, SEL swizzledSel) {
    Method origMethod = class_getClassMethod(cls, origSel);
    Method swizzledMethod = class_getClassMethod(cls, swizzledSel);
    method_exchangeImplementations(origMethod, swizzledMethod);
}

void swizzleClassMethod(Class class, SEL originalAction, SEL swizzledAction) {
    method_exchangeImplementations(class_getClassMethod(class, originalAction), class_getClassMethod(class, swizzledAction));
}
