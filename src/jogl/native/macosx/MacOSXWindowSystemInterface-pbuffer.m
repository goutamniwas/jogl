#import "MacOSXWindowSystemInterface.h"
#import <QuartzCore/QuartzCore.h>
#import <pthread.h>
#include "timespec.h"

// 
// CADisplayLink only available on iOS >= 3.1, sad, since it's convenient.
// Use CVDisplayLink otherwise.
//
// #define HAS_CADisplayLink 1
//

// lock/sync debug output
//
// #define DBG_SYNC 1
//
#ifdef DBG_SYNC
    // #define SYNC_PRINT(...) NSLog(@ ## __VA_ARGS__)
    #define SYNC_PRINT(...) fprintf(stderr, __VA_ARGS__); fflush(stderr)
#else
    #define SYNC_PRINT(...)
#endif

// fps debug output
//
// #define DBG_PERF 1

@interface MyNSOpenGLLayer: NSOpenGLLayer
{
@protected
    NSOpenGLPixelBuffer* pbuffer;
    int texWidth;
    int texHeight;
    GLuint textureID;
#ifdef HAS_CADisplayLink
    CADisplayLink* displayLink;
#else
    CVDisplayLinkRef displayLink;
#endif
    int tc;
    struct timespec t0;
@public
    struct timespec lastWaitTime;
    GLint swapInterval;
    GLint swapIntervalCounter;
    pthread_mutex_t renderLock;
    pthread_cond_t renderSignal;
    BOOL shallDraw;
}

- (id) setupWithContext: (NSOpenGLContext*) ctx
       pixelFormat: (NSOpenGLPixelFormat*) pfmt
       pbuffer: (NSOpenGLPixelBuffer*) p
       opaque: (Bool) opaque
       texWidth: (int) texWidth 
       texHeight: (int) texHeight;

- (void)deallocTex;
- (void)disableAnimation;
- (void)releaseLayer;
- (void)dealloc;
- (int)getSwapInterval;
- (void)setSwapInterval:(int)interval;
- (void)tick;

@end

#ifndef HAS_CADisplayLink

static CVReturn renderMyNSOpenGLLayer(CVDisplayLinkRef displayLink, 
                                      const CVTimeStamp *inNow, 
                                      const CVTimeStamp *inOutputTime, 
                                      CVOptionFlags flagsIn, 
                                      CVOptionFlags *flagsOut, 
                                      void *displayLinkContext)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    MyNSOpenGLLayer* l = (MyNSOpenGLLayer*)displayLinkContext;
    pthread_mutex_lock(&l->renderLock);
    #ifdef DBG_PERF
        [l tick];
    #endif
    if(0 < l->swapInterval) {
        l->swapIntervalCounter++;
        if(l->swapIntervalCounter>=l->swapInterval) {
            l->swapIntervalCounter = 0;
            pthread_cond_signal(&l->renderSignal);
            SYNC_PRINT("S");
        }
    }
    pthread_mutex_unlock(&l->renderLock);
    [pool release];
    return kCVReturnSuccess;
}

#endif

@implementation MyNSOpenGLLayer

- (id) setupWithContext: (NSOpenGLContext*) _ctx
       pixelFormat: (NSOpenGLPixelFormat*) _fmt
       pbuffer: (NSOpenGLPixelBuffer*) p
       opaque: (Bool) opaque
       texWidth: (int) _texWidth 
       texHeight: (int) _texHeight;
{
    pthread_mutexattr_t renderLockAttr;
    pthread_mutexattr_init(&renderLockAttr);
    pthread_mutexattr_settype(&renderLockAttr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&renderLock, &renderLockAttr); // recursive
    pthread_cond_init(&renderSignal, NULL); // no attribute

    textureID = 0;
    swapInterval = 1; // defaults to on (as w/ new GL profiles)
    swapIntervalCounter = 0;
    timespec_now(&lastWaitTime);
    shallDraw = NO;
    texWidth = _texWidth;
    texHeight = _texHeight;
    pbuffer = p;
    [pbuffer retain];

    {
        CGRect lRect = CGRectMake(0, 0, texWidth, texHeight);
        [self setFrame:lRect];

        // no animations for add/remove/swap sublayers etc 
        // doesn't work: [self removeAnimationForKey: kCAOnOrderIn, kCAOnOrderOut, kCATransition]
        [self removeAllAnimations];
    }

    // instantiate a deactivated displayLink
#ifdef HAS_CADisplayLink
    displayLink = [[CVDisplayLink displayLinkWithTarget:self selector:@selector(setNeedsDisplay)] retain];
    [displayLink setPaused: YES];
#else
    CVReturn cvres;
    {
        int allDisplaysMask = 0;
        int virtualScreen, accelerated, displayMask;
        for (virtualScreen = 0; virtualScreen < [_fmt  numberOfVirtualScreens]; virtualScreen++) {
            [_fmt getValues:&displayMask forAttribute:NSOpenGLPFAScreenMask forVirtualScreen:virtualScreen];
            [_fmt getValues:&accelerated forAttribute:NSOpenGLPFAAccelerated forVirtualScreen:virtualScreen];
            if (accelerated) {
                allDisplaysMask |= displayMask;
            }
        }
        cvres = CVDisplayLinkCreateWithOpenGLDisplayMask(allDisplaysMask, &displayLink);
        if(kCVReturnSuccess != cvres) {
            DBG_PRINT("MyNSOpenGLLayer::init %p, CVDisplayLinkCreateWithOpenGLDisplayMask %X failed: %d\n", self, allDisplaysMask, cvres);
            displayLink = NULL;
        }
    }
    if(NULL != displayLink) {
        cvres = CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink, [_ctx CGLContextObj], [_fmt CGLPixelFormatObj]);
        if(kCVReturnSuccess != cvres) {
            DBG_PRINT("MyNSOpenGLLayer::init %p, CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext failed: %d\n", self, cvres);
            displayLink = NULL;
        }
    }
    if(NULL != displayLink) {
        cvres = CVDisplayLinkSetOutputCallback(displayLink, renderMyNSOpenGLLayer, self);
        if(kCVReturnSuccess != cvres) {
            DBG_PRINT("MyNSOpenGLLayer::init %p, CVDisplayLinkSetOutputCallback failed: %d\n", self, cvres);
            displayLink = NULL;
        }
    }
    if(NULL != displayLink) {
        CVDisplayLinkStop(displayLink);
    }
#endif
    [self setAsynchronous: YES];

    [self setNeedsDisplayOnBoundsChange: YES];

    [self setOpaque: opaque ? YES : NO];

    CGRect lRect = [self frame];
    DBG_PRINT("MyNSOpenGLLayer::init %p, ctx %p, pfmt %p, pbuffer %p, opaque %d, pbuffer %dx%d -> tex %dx%d, frame: %lf/%lf %lfx%lf (refcnt %d)\n", 
        self, _ctx, _fmt, pbuffer, opaque, [pbuffer pixelsWide], [pbuffer pixelsHigh], texWidth, texHeight,
        lRect.origin.x, lRect.origin.y, lRect.size.width, lRect.size.height, (int)[self retainCount]);
    return self;
}

- (void)disableAnimation
{
    DBG_PRINT("MyNSOpenGLLayer::disableAnimation: %p (refcnt %d) - displayLink %p\n", self, (int)[self retainCount], displayLink);
    pthread_mutex_lock(&renderLock);
    [self setAsynchronous: NO];
    if(NULL != displayLink) {
#ifdef HAS_CADisplayLink
        [displayLink setPaused: YES];
        [displayLink release];
#else
        CVDisplayLinkStop(displayLink);
        CVDisplayLinkRelease(displayLink);
#endif
        displayLink = NULL;
    }
    pthread_mutex_unlock(&renderLock);
}

- (void)deallocTex
{
    pthread_mutex_lock(&renderLock);
    NSOpenGLContext* context = [self openGLContext];
    DBG_PRINT("MyNSOpenGLLayer::deallocTex %p (refcnt %d) - context %p, pbuffer %p\n", self, (int)[self retainCount], context, pbuffer);
    if(NULL != pbuffer) {
        if(NULL!=context) {
            [context makeCurrentContext];
            if(0 != textureID) {
                glDeleteTextures(1, &textureID);
                textureID = 0;
            }
            [context clearDrawable];
        }
        [pbuffer release];
        pbuffer = NULL;
    }
    pthread_mutex_unlock(&renderLock);
}

- (void)releaseLayer
{
    DBG_PRINT("MyNSOpenGLLayer::releaseLayer.0: %p (refcnt %d)\n", self, (int)[self retainCount]);
    pthread_mutex_lock(&renderLock);
    [self disableAnimation];
    [self deallocTex];
    [self release];
    DBG_PRINT("MyNSOpenGLLayer::releaseLayer.X: %p (refcnt %d)\n", self, (int)[self retainCount]);
    pthread_mutex_unlock(&renderLock);
}

- (void)dealloc
{
    DBG_PRINT("MyNSOpenGLLayer::dealloc.0 %p (refcnt %d)\n", self, (int)[self retainCount]);
    // NSLog(@"MyNSOpenGLLayer::dealloc: %@",[NSThread callStackSymbols]);

    [self disableAnimation];
    [self deallocTex];
    pthread_cond_destroy(&renderSignal);
    pthread_mutex_destroy(&renderLock);
    [super dealloc];
    DBG_PRINT("MyNSOpenGLLayer::dealloc.X %p\n", self);
}

- (BOOL)canDrawInOpenGLContext:(NSOpenGLContext *)context pixelFormat:(NSOpenGLPixelFormat *)pixelFormat 
        forLayerTime:(CFTimeInterval)timeInterval displayTime:(const CVTimeStamp *)timeStamp
{
    // assume both methods 'canDrawInOpenGLContext' and 'drawInOpenGLContext' 
    // are called from the same thread subsequently
    pthread_mutex_lock(&renderLock);
    Bool res = NULL != pbuffer && YES == shallDraw;
    if(!res) {
        SYNC_PRINT("0");
        pthread_mutex_unlock(&renderLock);
    } else {
        SYNC_PRINT("1");
    }
    return res;
}

- (void)drawInOpenGLContext:(NSOpenGLContext *)context pixelFormat:(NSOpenGLPixelFormat *)pixelFormat 
        forLayerTime:(CFTimeInterval)timeInterval displayTime:(const CVTimeStamp *)timeStamp
{
    [context makeCurrentContext];
   
    GLenum textureTarget = [pbuffer textureTarget];
    GLfloat texCoordWidth, texCoordHeight;
    {
        GLsizei pwidth = [pbuffer pixelsWide];
        GLsizei pheight = [pbuffer pixelsHigh];
        texCoordWidth  = textureTarget == GL_TEXTURE_2D ? (GLfloat)pwidth /(GLfloat)texWidth  : pwidth;
        texCoordHeight = textureTarget == GL_TEXTURE_2D ? (GLfloat)pheight/(GLfloat)texHeight : pheight;
    }
    Bool texCreated = 0 == textureID;
   
    if(texCreated) {
        glGenTextures(1, &textureID);

        CGRect lRect = [self frame];
        DBG_PRINT("MyNSOpenGLLayer::drawInOpenGLContext %p, pbuffer %p %dx%d -> tex %dx%d [%fx%f] id 0x%X target 0x%X, frame: %lf/%lf %lfx%lf (refcnt %d)\n", 
            self, pbuffer, [pbuffer pixelsWide], [pbuffer pixelsHigh], texWidth, texHeight, texCoordWidth, texCoordHeight, textureID, textureTarget,
            lRect.origin.x, lRect.origin.y, lRect.size.width, lRect.size.height, (int)[self retainCount]);
    }

    glBindTexture(textureTarget, textureID);

    /**
    if(texCreated) {
      // proper tex size setup
      glTexImage2D(textureTarget, 0, GL_RGB, texWidth, texHeight, 0, GL_RGB, GL_UNSIGNED_BYTE, NULL);
    } */

    [context setTextureImageToPixelBuffer: pbuffer colorBuffer: GL_FRONT];

    glTexParameteri(textureTarget, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(textureTarget, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(textureTarget, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(textureTarget, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
   
    glEnable(textureTarget);
   
    static GLfloat verts[] = {
    -1.0, -1.0,
    -1.0,  1.0,
     1.0,  1.0,
     1.0, -1.0
    };
   
    GLfloat tex[] = {
     0.0,           0.0,
     0.0,           texCoordHeight,
     texCoordWidth, texCoordHeight,
     texCoordWidth, 0.0
    };
   
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glVertexPointer(2, GL_FLOAT, 0, verts);
    glTexCoordPointer(2, GL_FLOAT, 0, tex);
   
    glDrawArrays(GL_QUADS, 0, 4);
   
    glDisableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
   
    glDisable(textureTarget);
    glBindTexture(textureTarget, 0);
   
    [super drawInOpenGLContext: context pixelFormat: pixelFormat forLayerTime: timeInterval displayTime: timeStamp];
    shallDraw = NO;
    if(0 >= swapInterval) {
        pthread_cond_signal(&renderSignal); // just to wake up
        SYNC_PRINT("s");
    }
    SYNC_PRINT("$");
    pthread_mutex_unlock(&renderLock);
}

- (int)getSwapInterval
{
    return swapInterval;
}

- (void)setSwapInterval:(int)interval
{
    /**
     * v-sync doesn't works w/ NSOpenGLLayer's context .. well :(
     * Using CVDisplayLink .. see setSwapInterval() below.
     *
        GLint si;
        [context getValues: &si forParameter: NSOpenGLCPSwapInterval];
        if(si != swapInterval) {
            DBG_PRINT("MyNSOpenGLLayer::drawInOpenGLContext %p setSwapInterval: %d -> %d\n", self, si, swapInterval);
            [context setValues: &swapInterval forParameter: NSOpenGLCPSwapInterval];
        }
    } */

    pthread_mutex_lock(&renderLock);
    DBG_PRINT("MyNSOpenGLLayer::setSwapInterval.0: %d - displayLink %p\n", interval, displayLink);
    swapInterval = interval;
    swapIntervalCounter = 0;
    pthread_mutex_unlock(&renderLock);

    if(NULL!=displayLink) {
        if(0 < swapInterval) {
            tc = 0;
            timespec_now(&t0);

            [self setAsynchronous: NO];
            #ifdef HAS_CADisplayLink
                [displayLink setPaused: NO];
                [displayLink setFrameInterval: interval];
            #else
                DBG_PRINT("MyNSOpenGLLayer::setSwapInterval.1.b.1\n");
                CVDisplayLinkStart(displayLink);
                DBG_PRINT("MyNSOpenGLLayer::setSwapInterval.1.b.X\n");
            #endif
        } else {
            #ifdef HAS_CADisplayLink
                [displayLink setPaused: YES];
            #else
                DBG_PRINT("MyNSOpenGLLayer::setSwapInterval.0.b.1\n");
                CVDisplayLinkStop(displayLink);
                DBG_PRINT("MyNSOpenGLLayer::setSwapInterval.0.b.X\n");
            #endif
            [self setAsynchronous: YES];
        }
    }
    DBG_PRINT("MyNSOpenGLLayer::setSwapInterval.X: %d\n", interval);
}

-(void)tick
{
    tc++;
    if(tc%60==0) {
        struct timespec t1, td;
        timespec_now(&t1);
        timespec_subtract(&td, &t1, &t0);
        long td_ms = timespec_milliseconds(&td);
        fprintf(stderr, "NSOpenGLLayer: %ld ms / %d frames, %ld ms / frame, %f fps\n",
            td_ms, tc, td_ms/tc, (tc * 1000.0) / (float)td_ms );
        fflush(NULL);
    }
}

@end

NSOpenGLLayer* createNSOpenGLLayer(NSOpenGLContext* ctx, NSOpenGLPixelFormat* fmt, NSOpenGLPixelBuffer* p, Bool opaque, int texWidth, int texHeight) {
  // This simply crashes after dealloc() has been called .. ie. ref-count -> 0 too early ?
  // However using alloc/init, actual dealloc happens at JAWT destruction, hence too later IMHO.
  // return [[MyNSOpenGLLayer layer] setupWithContext:ctx pixelFormat: fmt pbuffer: p opaque: opaque texWidth: texWidth texHeight: texHeight];

  return [[[MyNSOpenGLLayer alloc] init] setupWithContext:ctx pixelFormat: fmt pbuffer: p opaque: opaque texWidth: texWidth texHeight: texHeight];
}

void setNSOpenGLLayerSwapInterval(NSOpenGLLayer* layer, int interval) {
  MyNSOpenGLLayer* l = (MyNSOpenGLLayer*) layer;
  [l setSwapInterval: interval];
}

void waitUntilNSOpenGLLayerIsReady(NSOpenGLLayer* layer, long to_micros) {
    MyNSOpenGLLayer* l = (MyNSOpenGLLayer*) layer;
    BOOL ready = NO;
    int wr = 0;
    pthread_mutex_lock(&l->renderLock);
    SYNC_PRINT("{");
    do {
        if([l getSwapInterval] <= 0) {
            ready = !l->shallDraw;
        }
        if(NO == ready) {
            if(0 < to_micros) {
                #ifdef DBG_SYNC
                    struct timespec t0, t1, td, td2;
                    timespec_now(&t0);
                #endif
                struct timespec to_abs = l->lastWaitTime;
                timespec_addmicros(&to_abs, to_micros);
                #ifdef DBG_SYNC
                    timespec_subtract(&td, &to_abs, &t0);
                    fprintf(stderr, "(%ld) / ", timespec_milliseconds(&td));
                #endif
                wr = pthread_cond_timedwait(&l->renderSignal, &l->renderLock, &to_abs);
                #ifdef DBG_SYNC
                    timespec_now(&t1);
                    timespec_subtract(&td, &t1, &t0);
                    timespec_subtract(&td2, &t1, &l->lastWaitTime);
                    fprintf(stderr, "(%ld) / (%ld) ms", timespec_milliseconds(&td), timespec_milliseconds(&td2));
                #endif
            } else {
                pthread_cond_wait (&l->renderSignal, &l->renderLock);
            }
            ready = !l->shallDraw;
        }
    } while (NO == ready && 0 == wr) ;
    SYNC_PRINT("-%d}", ready);
    timespec_now(&l->lastWaitTime);
    pthread_mutex_unlock(&l->renderLock);
}

void setNSOpenGLLayerNeedsDisplay(NSOpenGLLayer* layer) {
    MyNSOpenGLLayer* l = (MyNSOpenGLLayer*) layer;
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    pthread_mutex_lock(&l->renderLock);
    l->shallDraw = YES;
    if ( [NSThread isMainThread] == YES ) {
      [l setNeedsDisplay];
    } else {
      // can't wait, otherwise we may deadlock AWT
      [l performSelectorOnMainThread:@selector(setNeedsDisplay) withObject:nil waitUntilDone:NO];
    }
    SYNC_PRINT(".");
    pthread_mutex_unlock(&l->renderLock);
    // DBG_PRINT("MyNSOpenGLLayer::setNSOpenGLLayerNeedsDisplay %p\n", l);
    [pool release];
}

void releaseNSOpenGLLayer(NSOpenGLLayer* layer) {
    MyNSOpenGLLayer* l = (MyNSOpenGLLayer*) layer;
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    DBG_PRINT("MyNSOpenGLLayer::releaseNSOpenGLLayer.0: %p\n", l);

    if ( [NSThread isMainThread] == YES ) {
        [l releaseLayer];
    } else { 
        [l performSelectorOnMainThread:@selector(releaseLayer) withObject:nil waitUntilDone:NO];
    }

    DBG_PRINT("MyNSOpenGLLayer::releaseNSOpenGLLayer.X: %p\n", l);
    [pool release];
}

