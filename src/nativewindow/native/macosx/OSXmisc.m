/**
 * Copyright 2011 JogAmp Community. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification, are
 * permitted provided that the following conditions are met:
 * 
 *    1. Redistributions of source code must retain the above copyright notice, this list of
 *       conditions and the following disclaimer.
 * 
 *    2. Redistributions in binary form must reproduce the above copyright notice, this list
 *       of conditions and the following disclaimer in the documentation and/or other materials
 *       provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY JogAmp Community ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 * FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL JogAmp Community OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 * ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * The views and conclusions contained in the software and documentation are those of the
 * authors and should not be interpreted as representing official policies, either expressed
 * or implied, of JogAmp Community.
 */
 
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <AppKit/AppKit.h>

#include "NativewindowCommon.h"
#include "jogamp_nativewindow_macosx_OSXUtil.h"
#include "jogamp_nativewindow_jawt_macosx_MacOSXJAWTWindow.h"

#include <jawt_md.h>
#import <JavaNativeFoundation.h>

// #define VERBOSE 1
//
#ifdef VERBOSE
    // #define DBG_PRINT(...) NSLog(@ ## __VA_ARGS__)
    #define DBG_PRINT(...) fprintf(stderr, __VA_ARGS__); fflush(stderr)
#else
    #define DBG_PRINT(...)
#endif

static const char * const ClazzNameRunnable = "java/lang/Runnable";
static jmethodID runnableRunID = NULL;

static const char * const ClazzAnyCstrName = "<init>";

static const char * const ClazzNamePoint = "javax/media/nativewindow/util/Point";
static const char * const ClazzNamePointCstrSignature = "(II)V";
static jclass pointClz = NULL;
static jmethodID pointCstr = NULL;

static const char * const ClazzNameInsets = "javax/media/nativewindow/util/Insets";
static const char * const ClazzNameInsetsCstrSignature = "(IIII)V";
static jclass insetsClz = NULL;
static jmethodID insetsCstr = NULL;

static int _initialized=0;

JNIEXPORT jboolean JNICALL 
Java_jogamp_nativewindow_macosx_OSXUtil_initIDs0(JNIEnv *env, jclass _unused) {
    if(0==_initialized) {
        jclass c;
        c = (*env)->FindClass(env, ClazzNamePoint);
        if(NULL==c) {
            NativewindowCommon_FatalError(env, "FatalError Java_jogamp_newt_driver_macosx_MacWindow_initIDs0: can't find %s", ClazzNamePoint);
        }
        pointClz = (jclass)(*env)->NewGlobalRef(env, c);
        (*env)->DeleteLocalRef(env, c);
        if(NULL==pointClz) {
            NativewindowCommon_FatalError(env, "FatalError Java_jogamp_newt_driver_macosx_MacWindow_initIDs0: can't use %s", ClazzNamePoint);
        }
        pointCstr = (*env)->GetMethodID(env, pointClz, ClazzAnyCstrName, ClazzNamePointCstrSignature);
        if(NULL==pointCstr) {
            NativewindowCommon_FatalError(env, "FatalError Java_jogamp_newt_driver_macosx_MacWindow_initIDs0: can't fetch %s.%s %s",
                ClazzNamePoint, ClazzAnyCstrName, ClazzNamePointCstrSignature);
        }

        c = (*env)->FindClass(env, ClazzNameInsets);
        if(NULL==c) {
            NativewindowCommon_FatalError(env, "FatalError Java_jogamp_newt_driver_macosx_MacWindow_initIDs0: can't find %s", ClazzNameInsets);
        }
        insetsClz = (jclass)(*env)->NewGlobalRef(env, c);
        (*env)->DeleteLocalRef(env, c);
        if(NULL==insetsClz) {
            NativewindowCommon_FatalError(env, "FatalError Java_jogamp_newt_driver_macosx_MacWindow_initIDs0: can't use %s", ClazzNameInsets);
        }
        insetsCstr = (*env)->GetMethodID(env, insetsClz, ClazzAnyCstrName, ClazzNameInsetsCstrSignature);
        if(NULL==insetsCstr) {
            NativewindowCommon_FatalError(env, "FatalError Java_jogamp_newt_driver_macosx_MacWindow_initIDs0: can't fetch %s.%s %s",
                ClazzNameInsets, ClazzAnyCstrName, ClazzNameInsetsCstrSignature);
        }

        c = (*env)->FindClass(env, ClazzNameRunnable);
        if(NULL==c) {
            NativewindowCommon_FatalError(env, "FatalError Java_jogamp_newt_driver_macosx_MacWindow_initIDs0: can't find %s", ClazzNameRunnable);
        }
        runnableRunID = (*env)->GetMethodID(env, c, "run", "()V");
        if(NULL==runnableRunID) {
            NativewindowCommon_FatalError(env, "FatalError Java_jogamp_newt_driver_macosx_MacWindow_initIDs0: can't fetch %s.run()V", ClazzNameRunnable);
        }
        _initialized=1;
    }
    return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL 
Java_jogamp_nativewindow_macosx_OSXUtil_isNSView0(JNIEnv *env, jclass _unused, jlong object) {
    NSObject *nsObj = (NSObject*) (intptr_t) object;
    return [nsObj isMemberOfClass:[NSView class]];
}

/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    getLocationOnScreen0
 * Signature: (JII)Ljavax/media/nativewindow/util/Point;
 */
JNIEXPORT jobject JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_GetLocationOnScreen0
  (JNIEnv *env, jclass unused, jlong winOrView, jint src_x, jint src_y)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    /**
     * return location in 0/0 top-left space,
     * OSX is 0/0 bottom-left space naturally
     */
    NSRect r;
    int dest_x=-1;
    int dest_y=-1;

    NSObject *nsObj = (NSObject*) (intptr_t) winOrView;
    NSWindow* win = NULL;
    NSView* view = NULL;

    if( [nsObj isKindOfClass:[NSWindow class]] ) {
        win = (NSWindow*) nsObj;
        view = [win contentView];
    } else if( nsObj != NULL && [nsObj isKindOfClass:[NSView class]] ) {
        view = (NSView*) nsObj;
        win = [view window];
    } else {
        NativewindowCommon_throwNewRuntimeException(env, "neither win not view %p\n", nsObj);
    }
    NSScreen* screen = [win screen];
    NSRect screenRect = [screen frame];
    NSRect winFrame = [win frame];

    r.origin.x = src_x;
    r.origin.y = winFrame.size.height - src_y; // y-flip for 0/0 top-left
    r.size.width = 0;
    r.size.height = 0;
    // NSRect rS = [win convertRectToScreen: r]; // 10.7
    NSPoint oS = [win convertBaseToScreen: r.origin];
    /**
    NSLog(@"LOS.1: (bottom-left) %d/%d, screen-y[0: %d, h: %d], (top-left) %d/%d\n", 
        (int)oS.x, (int)oS.y, (int)screenRect.origin.y, (int) screenRect.size.height,
        (int)oS.x, (int)(screenRect.origin.y + screenRect.size.height - oS.y)); */

    dest_x = (int) oS.x;
    dest_y = (int) screenRect.origin.y + screenRect.size.height - oS.y;

    jobject res = (*env)->NewObject(env, pointClz, pointCstr, (jint)dest_x, (jint)dest_y);

    [pool release];

    return res;
}

/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    getInsets0
 * Signature: (J)Ljavax/media/nativewindow/util/Insets;
 */
JNIEXPORT jobject JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_GetInsets0
  (JNIEnv *env, jclass unused, jlong winOrView)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    NSObject *nsObj = (NSObject*) (intptr_t) winOrView;
    NSWindow* win = NULL;
    NSView* view = NULL;
    jint il,ir,it,ib;

    if( [nsObj isKindOfClass:[NSWindow class]] ) {
        win = (NSWindow*) nsObj;
        view = [win contentView];
    } else if( nsObj != NULL && [nsObj isKindOfClass:[NSView class]] ) {
        view = (NSView*) nsObj;
        win = [view window];
    } else {
        NativewindowCommon_throwNewRuntimeException(env, "neither win not view %p\n", nsObj);
    }

    NSRect frameRect = [win frame];
    NSRect contentRect = [win contentRectForFrameRect: frameRect];

    // note: this is a simplistic implementation which doesn't take
    // into account DPI and scaling factor
    CGFloat l = contentRect.origin.x - frameRect.origin.x;
    il = (jint)l;                                                     // l
    ir = (jint)(frameRect.size.width - (contentRect.size.width + l)); // r
    it = (jint)(frameRect.size.height - contentRect.size.height);     // t
    ib = (jint)(contentRect.origin.y - frameRect.origin.y);           // b

    jobject res = (*env)->NewObject(env, insetsClz, insetsCstr, il, ir, it, ib);

    [pool release];

    return res;
}

/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    CreateNSWindow0
 * Signature: (IIIIZ)J
 */
JNIEXPORT jlong JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_CreateNSWindow0
  (JNIEnv *env, jclass unused, jint x, jint y, jint width, jint height)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    NSRect rect = NSMakeRect(x, y, width, height);

    // Allocate the window
    NSWindow* myWindow = [[NSWindow alloc] initWithContentRect: rect
                                           styleMask: NSBorderlessWindowMask
                                           backing: NSBackingStoreBuffered
                                           defer: YES];
    [myWindow setReleasedWhenClosed: YES]; // default
    [myWindow setPreservesContentDuringLiveResize: YES];
    // Remove animations
NS_DURING
        // Available >= 10.7 - Removes default animations
        [myWindow setAnimationBehavior: NSWindowAnimationBehaviorNone];
NS_HANDLER
NS_ENDHANDLER

    // invisible ..
    [myWindow setOpaque: NO];
    [myWindow setBackgroundColor: [NSColor clearColor]];

    [pool release];

    return (jlong) ((intptr_t) myWindow);
}

/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    DestroyNSWindow0
 * Signature: (J)V
 */
JNIEXPORT void JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_DestroyNSWindow0
  (JNIEnv *env, jclass unused, jlong nsWindow)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    NSWindow* mWin = (NSWindow*) ((intptr_t) nsWindow);

    [mWin close]; // performs release!
    [pool release];
}

/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    GetNSView0
 * Signature: (J)J
 */
JNIEXPORT jlong JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_GetNSView0
  (JNIEnv *env, jclass unused, jlong window)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    NSWindow* win = (NSWindow*) ((intptr_t) window);

    DBG_PRINT( "contentView0 - window: %p (START)\n", win);

    jlong res = (jlong) ((intptr_t) [win contentView]);

    DBG_PRINT( "contentView0 - window: %p (END)\n", win);

    [pool release];
    return res;
}

/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    CreateCALayer0
 * Signature: (IIII)J
 */
JNIEXPORT jlong JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_CreateCALayer0
  (JNIEnv *env, jclass unused, jint x, jint y, jint width, jint height)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    CALayer* layer = [[CALayer alloc] init];
    DBG_PRINT("CALayer::CreateCALayer.0: %p %d/%d %dx%d (refcnt %d)\n", layer, (int)x, (int)y, (int)width, (int)height, (int)[layer retainCount]);
    // avoid zero size
    if(0 == width) { width = 32; }
    if(0 == height) { height = 32; }

    // initial dummy size !
    CGRect lRect = [layer frame];
    lRect.origin.x = x;
    lRect.origin.y = y;
    lRect.size.width = width;
    lRect.size.height = height;
    [layer setFrame: lRect];
    // no animations for add/remove/swap sublayers etc 
    // doesn't work: [layer removeAnimationForKey: kCAOnOrderIn, kCAOnOrderOut, kCATransition]
    [layer removeAllAnimations];
    DBG_PRINT("CALayer::CreateCALayer.1: %p %lf/%lf %lfx%lf\n", layer, lRect.origin.x, lRect.origin.y, lRect.size.width, lRect.size.height);
    DBG_PRINT("CALayer::CreateCALayer.X: %p (refcnt %d)\n", layer, (int)[layer retainCount]);

    [pool release];

    return (jlong) ((intptr_t) layer);
}

/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    AddCASublayer0
 * Signature: (JJ)V
 */
JNIEXPORT void JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_AddCASublayer0
  (JNIEnv *env, jclass unused, jlong rootCALayer, jlong subCALayer)
{
    JNF_COCOA_ENTER(env);
    CALayer* rootLayer = (CALayer*) ((intptr_t) rootCALayer);
    CALayer* subLayer = (CALayer*) ((intptr_t) subCALayer);

    CGRect lRectRoot = [rootLayer frame];
    DBG_PRINT("CALayer::AddCASublayer0.0: Origin %p frame0: %lf/%lf %lfx%lf\n", 
        rootLayer, lRectRoot.origin.x, lRectRoot.origin.y, lRectRoot.size.width, lRectRoot.size.height);
    if(lRectRoot.origin.x!=0 || lRectRoot.origin.y!=0) {
        lRectRoot.origin.x = 0;
        lRectRoot.origin.y = 0;
        [JNFRunLoop performOnMainThreadWaiting:YES withBlock:^(){
            [rootLayer setFrame: lRectRoot];
        }];
        DBG_PRINT("CALayer::AddCASublayer0.1: Origin %p frame*: %lf/%lf %lfx%lf\n", 
            rootLayer, lRectRoot.origin.x, lRectRoot.origin.y, lRectRoot.size.width, lRectRoot.size.height);
    }
    DBG_PRINT("CALayer::AddCASublayer0.2: %p . %p %lf/%lf %lfx%lf (refcnt %d)\n", 
        rootLayer, subLayer, lRectRoot.origin.x, lRectRoot.origin.y, lRectRoot.size.width, lRectRoot.size.height, (int)[subLayer retainCount]);

    [JNFRunLoop performOnMainThreadWaiting:YES withBlock:^(){
        // simple 1:1 layout !
        [subLayer setFrame:lRectRoot];
        [rootLayer addSublayer:subLayer];

        // no animations for add/remove/swap sublayers etc 
        // doesn't work: [layer removeAnimationForKey: kCAOnOrderIn, kCAOnOrderOut, kCATransition]
        [rootLayer removeAllAnimations];
        [subLayer removeAllAnimations];
    }];
    DBG_PRINT("CALayer::AddCASublayer0.X: %p . %p (refcnt %d)\n", rootLayer, subLayer, (int)[subLayer retainCount]);
    JNF_COCOA_EXIT(env);
}

/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    RemoveCASublayer0
 * Signature: (JJ)V
 */
JNIEXPORT void JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_RemoveCASublayer0
  (JNIEnv *env, jclass unused, jlong rootCALayer, jlong subCALayer)
{
    JNF_COCOA_ENTER(env);
    CALayer* rootLayer = (CALayer*) ((intptr_t) rootCALayer);
    CALayer* subLayer = (CALayer*) ((intptr_t) subCALayer);

    (void)rootLayer; // no warnings

    DBG_PRINT("CALayer::RemoveCASublayer0.0: %p . %p (refcnt %d)\n", rootLayer, subLayer, (int)[subLayer retainCount]);
    [JNFRunLoop performOnMainThreadWaiting:YES withBlock:^(){
        [subLayer removeFromSuperlayer];
    }];
    DBG_PRINT("CALayer::RemoveCASublayer0.X: %p . %p\n", rootLayer, subLayer);
    JNF_COCOA_EXIT(env);
}

/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    DestroyCALayer0
 * Signature: (J)V
 */
JNIEXPORT void JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_DestroyCALayer0
  (JNIEnv *env, jclass unused, jlong caLayer)
{
    JNF_COCOA_ENTER(env);
    CALayer* layer = (CALayer*) ((intptr_t) caLayer);

    DBG_PRINT("CALayer::DestroyCALayer0.0: %p (refcnt %d)\n", layer, (int)[layer retainCount]);
    [JNFRunLoop performOnMainThreadWaiting:YES withBlock:^(){
        [layer release]; // performs release!
    }];
    DBG_PRINT("CALayer::DestroyCALayer0.X: %p\n", layer);
    JNF_COCOA_EXIT(env);
}

@interface MainRunnable : NSObject

{
    JavaVM *jvmHandle;
    int jvmVersion;
    jobject runnableObj;
}

- (id) initWithRunnable: (jobject)runnable jvmHandle: (JavaVM*)jvm jvmVersion: (int)jvmVers;
- (void) jRun;

@end

@implementation MainRunnable

- (id) initWithRunnable: (jobject)runnable jvmHandle: (JavaVM*)jvm jvmVersion: (int)jvmVers
{
    jvmHandle = jvm;
    jvmVersion = jvmVers;
    runnableObj = runnable;
    return [super init];
}

- (void) jRun
{
    int shallBeDetached = 0;
    JNIEnv* env = NativewindowCommon_GetJNIEnv(jvmHandle, jvmVersion, &shallBeDetached);
    if(NULL!=env) {
        (*env)->CallVoidMethod(env, runnableObj, runnableRunID);

        if (shallBeDetached) {
            (*jvmHandle)->DetachCurrentThread(jvmHandle);
        }
    }
}

@end


/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    RunOnMainThread0
 * Signature: (ZLjava/lang/Runnable;)V
 */
JNIEXPORT void JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_RunOnMainThread0
  (JNIEnv *env, jclass unused, jboolean jwait, jobject runnable)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    if ( NO == [NSThread isMainThread] ) {
        jobject runnableGlob = (*env)->NewGlobalRef(env, runnable);

        BOOL wait = (JNI_TRUE == jwait) ? YES : NO;
        JavaVM *jvmHandle = NULL;
        int jvmVersion = 0;

        if(0 != (*env)->GetJavaVM(env, &jvmHandle)) {
            jvmHandle = NULL;
        } else {
            jvmVersion = (*env)->GetVersion(env);
        }

        MainRunnable * mr = [[MainRunnable alloc] initWithRunnable: runnableGlob jvmHandle: jvmHandle jvmVersion: jvmVersion];
        [mr performSelectorOnMainThread:@selector(jRun) withObject:nil waitUntilDone:wait];
        [mr release];

        (*env)->DeleteGlobalRef(env, runnableGlob);
    } else {
        (*env)->CallVoidMethod(env, runnable, runnableRunID);
    }

    [pool release];
}

/*
 * Class:     Java_jogamp_nativewindow_macosx_OSXUtil
 * Method:    RunOnMainThread0
 * Signature: (V)V
 */
JNIEXPORT jboolean JNICALL Java_jogamp_nativewindow_macosx_OSXUtil_IsMainThread0
  (JNIEnv *env, jclass unused)
{
    return ( [NSThread isMainThread] == YES ) ? JNI_TRUE : JNI_FALSE ;
}

/*
 * Class:     Java_jogamp_nativewindow_jawt_macosx_MacOSXJAWTWindow
 * Method:    SetJAWTRootSurfaceLayer0
 * Signature: (JJ)Z
 */
JNIEXPORT jboolean JNICALL Java_jogamp_nativewindow_jawt_macosx_MacOSXJAWTWindow_SetJAWTRootSurfaceLayer0
  (JNIEnv *env, jclass unused, jobject jawtDrawingSurfaceInfoBuffer, jlong caLayer)
{
    JNF_COCOA_ENTER(env);
    JAWT_DrawingSurfaceInfo* dsi = (JAWT_DrawingSurfaceInfo*) (*env)->GetDirectBufferAddress(env, jawtDrawingSurfaceInfoBuffer);
    if (NULL == dsi) {
        NativewindowCommon_throwNewRuntimeException(env, "Argument \"jawtDrawingSurfaceInfoBuffer\" was not a direct buffer");
        return JNI_FALSE;
    }
    CALayer* layer = (CALayer*) (intptr_t) caLayer;
    [JNFRunLoop performOnMainThreadWaiting:YES withBlock:^(){
        id <JAWT_SurfaceLayers> surfaceLayers = (id <JAWT_SurfaceLayers>)dsi->platformInfo;
        DBG_PRINT("CALayer::SetJAWTRootSurfaceLayer.0: %p -> %p (refcnt %d)\n", surfaceLayers.layer, layer, (int)[layer retainCount]);
        surfaceLayers.layer = layer; // already incr. retain count
        DBG_PRINT("CALayer::SetJAWTRootSurfaceLayer.X: %p (refcnt %d)\n", layer, (int)[layer retainCount]);
    }];
    JNF_COCOA_EXIT(env);
    return JNI_TRUE;
}

/*
 * Class:     Java_jogamp_nativewindow_jawt_macosx_MacOSXJAWTWindow
 * Method:    UnsetJAWTRootSurfaceLayer0
 * Signature: (JJ)Z
JNIEXPORT jboolean JNICALL Java_jogamp_nativewindow_jawt_macosx_MacOSXJAWTWindow_UnsetJAWTRootSurfaceLayer0
  (JNIEnv *env, jclass unused, jobject jawtDrawingSurfaceInfoBuffer, jlong caLayer)
{
    JNF_COCOA_ENTER(env);
    JAWT_DrawingSurfaceInfo* dsi = (JAWT_DrawingSurfaceInfo*) (*env)->GetDirectBufferAddress(env, jawtDrawingSurfaceInfoBuffer);
    if (NULL == dsi) {
        NativewindowCommon_throwNewRuntimeException(env, "Argument \"jawtDrawingSurfaceInfoBuffer\" was not a direct buffer");
        return JNI_FALSE;
    }
    CALayer* layer = (CALayer*) (intptr_t) caLayer;
    {
        id <JAWT_SurfaceLayers> surfaceLayers = (id <JAWT_SurfaceLayers>)dsi->platformInfo;
        if(layer != surfaceLayers.layer) {
            NativewindowCommon_throwNewRuntimeException(env, "Attached layer %p doesn't match given layer %p\n", surfaceLayers.layer, layer);
            return JNI_FALSE;
        }
    }
    // [JNFRunLoop performOnMainThreadWaiting:YES withBlock:^(){
        id <JAWT_SurfaceLayers> surfaceLayers = (id <JAWT_SurfaceLayers>)dsi->platformInfo;
        DBG_PRINT("CALayer::detachJAWTSurfaceLayer: (%p) %p -> NULL\n", layer, surfaceLayers.layer);
        surfaceLayers.layer = NULL;
        [layer release];
    // }];
    JNF_COCOA_EXIT(env);
    return JNI_TRUE;
}
 */

