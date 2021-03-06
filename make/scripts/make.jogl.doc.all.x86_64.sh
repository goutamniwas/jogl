#! /bin/sh

SDIR=`dirname $0` 

if [ -e $SDIR/../../../gluegen/make/scripts/setenv-build-jogl-x86_64.sh ] ; then
    . $SDIR/../../../gluegen/make/scripts/setenv-build-jogl-x86_64.sh
fi

ant -v  \
    -Drootrel.build=build-x86_64 \
    javadoc.spec javadoc javadoc.dev $* 2>&1 | tee make.jogl.doc.all.x86_64.log
