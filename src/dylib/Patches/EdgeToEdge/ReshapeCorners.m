#import "EdgeToEdge.h"

// Keeps the same path elements so Dia's animations still interpolate.
CGPathRef DPReshapeCorners(CGPathRef path, CGFloat extent, CGFloat rightScale, CGFloat leftScale) {
    if (!path) return NULL;
    __block CGRect box = CGRectNull;
    __block int subpath = 0;
    CGPathApplyWithBlock(path, ^(const CGPathElement *element) {
        if (element->type == kCGPathElementMoveToPoint && !CGRectIsNull(box)) subpath++;
        int count = element->type == kCGPathElementAddCurveToPoint ? 3 : element->type == kCGPathElementAddQuadCurveToPoint ? 2
                  : element->type == kCGPathElementCloseSubpath ? 0 : 1;
        for (int i = 0; i < count && subpath == 0; i++) box = CGRectUnion(box, (CGRect){element->points[i], CGSizeZero});
    });
    CGMutablePathRef reshaped = CGPathCreateMutable();
    subpath = 0;
    __block BOOL started = NO;
    CGPoint (^move)(CGPoint) = ^CGPoint(CGPoint p) {
        if (subpath > 0) return p;
        CGFloat cx = p.x - CGRectGetMinX(box) < extent ? CGRectGetMinX(box) : CGRectGetMaxX(box) - p.x < extent ? CGRectGetMaxX(box) : NAN;
        CGFloat cy = p.y - CGRectGetMinY(box) < extent ? CGRectGetMinY(box) : CGRectGetMaxY(box) - p.y < extent ? CGRectGetMaxY(box) : NAN;
        if (isnan(cx) || isnan(cy)) return p;
        CGFloat scale = cx == CGRectGetMinX(box) ? leftScale : rightScale;
        return CGPointMake(cx + (p.x - cx) * scale, cy + (p.y - cy) * scale);
    };
    CGPathApplyWithBlock(path, ^(const CGPathElement *element) {
        const CGPoint *p = element->points;
        switch (element->type) {
            case kCGPathElementMoveToPoint: {
                if (started) subpath++;
                started = YES;
                CGPoint a = move(p[0]);
                CGPathMoveToPoint(reshaped, NULL, a.x, a.y);
                break;
            }
            case kCGPathElementAddLineToPoint: {
                CGPoint a = move(p[0]);
                CGPathAddLineToPoint(reshaped, NULL, a.x, a.y);
                break;
            }
            case kCGPathElementAddQuadCurveToPoint: {
                CGPoint a = move(p[0]), b = move(p[1]);
                CGPathAddQuadCurveToPoint(reshaped, NULL, a.x, a.y, b.x, b.y);
                break;
            }
            case kCGPathElementAddCurveToPoint: {
                CGPoint a = move(p[0]), b = move(p[1]), c = move(p[2]);
                CGPathAddCurveToPoint(reshaped, NULL, a.x, a.y, b.x, b.y, c.x, c.y);
                break;
            }
            case kCGPathElementCloseSubpath: CGPathCloseSubpath(reshaped); break;
        }
    });
    return (CGPathRef)CFAutorelease(reshaped);
}
