#! /bin/sh

BUILDDIR=$1
shift
if [ -z "$BUILDDIR" ] ; then
    echo "usage $0 <BUILDDIR>"
    exit 1
fi

idir=$BUILDDIR/jogl/gensrc/classes/javax/media/opengl

echo GL2 to GL3 enums
sort $idir/GL2.java $idir/GL3.java $idir/GL2ES2.java $idir/GL2GL3.java | uniq -u | grep GL_ | awk ' { print $5 } '

echo GL2 to GL3 functions
sort $idir/GL2.java $idir/GL3.java $idir/GL2ES2.java $idir/GL2GL3.java | uniq -u | grep "public [a-z0-9_]* gl"