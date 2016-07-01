#!/bin/bash

# script to build PyCBC suite on Debian Etch and Windows Cygwin

# FIXME/todo:
#

# check an md5 sum of a file, independent of platform
# $1 file to check, $2 md5 checksum
# returns 0 for fail, 1 for success(!)
check_md5() {
    md5s=`( md5sum $1 2>/dev/null || md5 $1 2>/dev/null) | sed 's/.* = //;s/  .*//;s/^\(................................\).*/\1/'`
    test ".$2" != ".$md5s"
}

trap 'exit 1' ERR

echo -e ">> [`date`] Start $0 $*"

test ".$LANG" = "." && export LANG="en_US.UTF-8"
test ".$LC_ALL" = "." && export LC_ALL="$LANG"
export FC=gfortran

# defaults, possibly overwritten by command-line arguments
cleanup=true # usually, build directories are removed after a successful build
verbose_pyinstalled_python=false
pycbc_branch=master
pycbc_remote=ligo-cbc
scratch_pycbc=false

# automatically detect a Debian 4.0 (Etch) installation.
# if not found, use Cygwin settings.
# "build" or "compile" here means "from source", opposed to
# expect it to be installed on the system or "pip install" it.
if test "v`cat /etc/debian_version 2>/dev/null`" = "v4.0"; then
    echo -e "\\n\\n>> [`date`] Using Debian 4.0 (etch) settings"
    test ".$LC_ALL" = "." && export LC_ALL="$LANG"
    fftw_flags=--enable-avx
    shared="--enable-shared"
    build_dlls=false
    build_ssl=true
    build_python=false
    build_lapack=true
    pyssl_from="tarball" # "pip-install"
    numpy_from="pip-install" # "tarball"
    scipy_from="git" # "git-patched" "pip-install"
    build_hdf5=true
    build_freetype=true
    build_libpq=false
    build_gsl=true
    build_swig=true
    build_framecpp=false
    h5py_from="git"
    glue_from="pip-install" # "git-patched"
    psycopg26_from=fake-psycopg255 # "pip-install" "system"
    build_pegasus_source=true
    build_preinst_before_lalsuite=false
    pyinstaller_version=9d0e0ad4 # 9d0e0ad4, v2.1, v3.0 or v3.1 -> git, 2.1 or 3.0 -> pypi
    pyinstaller_lsb="--no-lsb"
    use_pycbc_pyinstaller_hooks=true
    build_wrapper=false
    appendix="_Linux64"
elif test "`uname -s`" = "Darwin" ; then
    echo -e "\\n\\n>> [`date`] Using OSX 10.7 settings"
    export FC=gfortran-mp-4.8
    export CC=gcc-mp-4.8
    export CXX=g++-mp-4.8
    export FFLAGS=-m64
    export CFLAGS=-m64
    export CXXFLAGS=-m64
    export LDFLAGS=-m64
#    libframe_debug_level=3
#    lal_cppflags="-DDONT_RESOLVE_LALCACHE_PATH"
    shared="--enable-shared"
    build_dlls=false
    build_ssl=false
    build_python=false
    build_lapack=true
    pyssl_from="tarball" # "pip-install"
    numpy_from="pip-install" # "tarball"
    scipy_from="pip-install" # "git" "git-patched" "pip-install"
    build_hdf5=true
    build_freetype=true
    build_libpq=false
    build_gsl=true
    build_swig=true
    build_framecpp=true
    h5py_from="pip-install" # "git"
    glue_from="pip-install" # "git-patched"
    psycopg26_from=system
    build_pegasus_source=false
    build_preinst_before_lalsuite=true
    pyinstaller_version=9d0e0ad4 # 9d0e0ad4, v2.1, v3.0 or v3.1 -> git, 2.1 or 3.0 -> pypi
    use_pycbc_pyinstaller_hooks=true
    build_wrapper=false
    appendix="_OSX64"
else
    echo -e "\\n\\n>> [`date`] Using Cygwin settings"
    fftw_flags=--enable-avx
    lal_cppflags="-D_WIN32"
    shared="--enable-shared"
    build_dlls=true
    build_ssl=false
    build_python=false
    build_lapack=true
    pyssl_from="tarball" # "pip-install"
    numpy_from="tarball" # "pip-install"
    scipy_from="git" # "git-patched" "pip-install"
    build_hdf5=false
    build_freetype=false
    build_libpq=false
    build_gsl=false
    build_swig=false
    build_framecpp=false
    glue_from="git-patched" # "pip-install"
    h5py_from="pip-install"
    psycopg26_from=fake-psycopg255 # "pip-install" "system"
    build_pegasus_source=false
    build_preinst_before_lalsuite=true
    pyinstaller_version=9d0e0ad4 # 9d0e0ad4, v2.1, v3.0 or v3.1 -> git, 2.1 or 3.0 -> pypi 
    use_pycbc_pyinstaller_hooks=true
    build_wrapper=false
    appendix="_Windows64"
fi

# compilation environment
PYCBC="$PWD/pycbc"
SOURCE="$PWD/pycbc-sources"
PYTHON_PREFIX="$PYCBC"
ENVIRONMENT="$PYCBC/environment"
PREFIX="$ENVIRONMENT"
PATH="$PREFIX/bin:$PYTHON_PREFIX/bin:$PATH:/opt/local//Library/Frameworks/Python.framework/Versions/2.7/bin"
libgfortran="`$FC -print-file-name=libgfortran.so|sed 's%/[^/]*$%%'`"
export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/bin:$PYTHON_PREFIX/lib:$libgfortran:/usr/local/lib:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PYTHON_PREFIX/lib/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
export LIBS="$LIBS -lgfortran"

# handle command-line arguments, possibly overriding above settings
for i in $*; do
    case $i in
        --no-pycbc-update) pycbc_branch="HEAD";;
        --scratch-pycbc) scratch_pycbc=true;;
        --bema-testing)
            pycbc_branch=einsteinathome_testing
            pycbc_remote=bema-ligo;;
        --no-cleanup) cleanup=false;;
        --verbose-python) verbose_pyinstalled_python=true;;
        --clean) rm -rf "$HOME/.cache" "$SOURCE/pycbc-preinst.tgz" "$SOURCE/pycbc-preinst-lalsuite.tgz";;
        --clean-lalsuite) rm -rf "$SOURCE/lalsuite" "$SOURCE/pycbc-preinst-lalsuite.tgz";;
        --lalsuite-commit=*) lalsuite_branch="`echo $i|sed 's/^--lalsuite-commit=//'`";;
        --clean-sundays)
            if [ `date +%u` -eq 7 ]; then
                if [ -r "$SOURCE/last_sunday_build" ]; then
                    last_build=`cat "$SOURCE/last_sunday_build"`
                else
                    last_build=0
                fi
                now=`date +%s`
                d2_ago=`expr $now - 172800` # two days ago
                if [  $last_build -le $d2_ago ]; then # last 'clean-sundays' build was two days ago or older
                    rm -rf "$HOME/.cache" "$SOURCE/pycbc-preinst.tgz" "$SOURCE/pycbc-preinst-lalsuite.tgz"
                    echo $now > "$SOURCE/last_sunday_build"
                fi
            fi ;;
        *) echo "unknown option '$i', valid are:

    --clean           : perform a clean build (takes quite some time); delete ~/.cache and
                        tarballs containing precompiled libraries (lalsuite, scipy etc.)
    --clean-lalsuite  : clean lalsuite before building, checkout and build it from scratch
    --clean-sundays   : perform a clean build on sundays
    --lalsuite-commit=<commit> : specify a commit (tag or branch) of lalsuite to build from
    --no-pycbc-update : don't update local pycbc repo from remote branch $pycbc_branch
    --bema-testing    : use einsteinathome_testing branch of bema-ligo pycbc repo
    --scratch-pycbc   : check out pycbc git repo from scratch
    --no-cleanup      : keep build directories after successful build for later inspection
    --verbose-python  : run PyInstalled Python in verbose mode, showing imports">&2; exit 1;;
    esac
done

# log environment
echo -e "\\n\\n>> [`date`] ENVIRONMENT ..."
env
echo -e "... ENVIRONMENT"

# hack to use the script as a frontend for a Cygwin build slave for a Jenkins job
# WORKSPACE='/Users/jenkins/workspace/workspace/EAH_PyCBC_Master/label/OSX107'
if echo ".$WORKSPACE" | grep CYGWIN64_FRONTEND >/dev/null; then
    test ".$CYGWIN_HOST" = "."      && CYGWIN_HOST=moss-cygwin64
    test ".$CYGWIN_HOST_USER" = "." && CYGWIN_HOST_USER=jenkins
    test ".$CYGWIN_HOST_PORT" = "." && CYGWIN_HOST_PORT=2222
    echo -e "\\n\\n>> [`date`] running remotely at $CYGWIN_HOST_USER@$CYGWIN_HOST:$CYGWIN_HOST_PORT"
    echo "WORKSPACE='$WORKSPACE'" # for Jenkins jobs
    unset WORKSPACE # avoid endless recoursion
    # copy the script
    scp "-P$CYGWIN_HOST_PORT" "$0" "$CYGWIN_HOST_USER@$CYGWIN_HOST:."
    # run it remotely
    ssh "-p$CYGWIN_HOST_PORT" "$CYGWIN_HOST_USER@$CYGWIN_HOST" bash -l `basename $0` "$@"
    # fetch the artifacts to local workspace
    dist="pycbc/environment/dist"
    rm -rf "$dist"
    mkdir -p "$dist"
    scp "-P$CYGWIN_HOST_PORT" "$CYGWIN_HOST_USER@$CYGWIN_HOST:$dist/*.exe" "$dist"
    scp "-P$CYGWIN_HOST_PORT" "$CYGWIN_HOST_USER@$CYGWIN_HOST:$dist/*.zip" "$dist"
    exit 0
fi

# log compilation environment
echo "export PATH='$PATH'"
echo "export LD_LIBRARY_PATH='$LD_LIBRARY_PATH'"
echo "export PKG_CONFIG_PATH='$PKG_CONFIG_PATH'"
echo "WORKSPACE='$WORKSPACE'" # for Jenkins jobs

# obsolete, kept for reference
#export CPPFLAGS="-I$PREFIX/include"
#export LDFLAGS="-L$PREFIX/lib -L$libgfortran"
#export LDFLAGS="-L$libgfortran $LDFLAGS"
# -static-libgfortran

# URL abbrevations
pypi="http://pypi.python.org/packages/source"
gitmaster="gitmaster.atlas.aei.uni-hannover.de/einsteinathome"
atlas="https://www.atlas.aei.uni-hannover.de/~bema"
albert=http://albert.phys.uwm.edu/download

# circumvent old certificate chains on old systems
export GIT_SSL_NO_VERIFY=true
wget_opts="-c --passive-ftp --no-check-certificate"
export PIP_TRUSTED_HOST="pypi.python.org github.com"

# make sure the sources directory exixts
mkdir -p "$SOURCE"

# use previously compiled scipy, lalsuite etc. if available
if test -r "$SOURCE/pycbc-preinst.tgz" -o -r "$SOURCE/pycbc-preinst-lalsuite.tgz"; then

    rm -rf pycbc
    if test -r "$SOURCE/pycbc-preinst-lalsuite.tgz"; then
	echo -e "\\n\\n>> [`date`] using pycbc-preinst-lalsuite.tgz"
	tar -xzf "$SOURCE/pycbc-preinst-lalsuite.tgz"
    else
	echo -e "\\n\\n>> [`date`] using pycbc-preinst.tgz"
	tar -xzf "$SOURCE/pycbc-preinst.tgz"
    fi
    # set up virtual environment
    unset PYTHONPATH
    source "$ENVIRONMENT/bin/activate"
    # workaround to make the virtualenv accept .pth files
    export PYTHONPATH="$PREFIX/lib/python2.7/site-packages:$PYTHONPATH"
    cd "$SOURCE"
    if ls $PREFIX/etc/*-user-env.sh >/dev/null 2>&1; then
	for i in $PREFIX/etc/*-user-env.sh; do
	    source "$i"
	done
    fi

else # if pycbc-preinst.tgz

    cd "$SOURCE"

    # OpenSSL
    if $build_ssl; then
    # p=openssl-1.0.2e # compile error on pyOpenSSL 0.13:
    # pycbc/include/openssl/x509.h:751: note: previous declaration X509_REVOKED_ was here
	p=openssl-1.0.1p
	echo -e "\\n\\n>> [`date`] building $p"
	test -r $p.tar.gz || wget $wget_opts $atlas/tarballs/$p.tar.gz
	rm -rf $p
	tar -xzvf $p.tar.gz  &&
	cd $p &&
	./config shared -fPIC "--prefix=$PYTHON_PREFIX" #  no-shared no-sse2 CFLAGS=-fPIC
	make
	make install
	cd ..
	$cleanup && rm -rf $p
    fi

    # PYTHON
    if $build_python; then
	v=2.7.10
	p=Python-$v
	echo -e "\\n\\n>> [`date`] building $p"
	test -r $p.tgz || wget $wget_opts http://www.python.org/ftp/python/$v/$p.tgz
	rm -rf $p
	tar -xzf $p.tgz
	cd $p
	./configure $shared --prefix="$PYTHON_PREFIX"
	make
	make install
	cd ..
	$cleanup && rm -rf $p
	python -m ensurepip
	echo -e "\\n\\n>> [`date`] pip install --upgrade pip"
	pip install --upgrade pip
	echo -e "\\n\\n>> [`date`] pip install virtualenv"
	pip install virtualenv
    fi

    # set up virtual environment
    unset PYTHONPATH
    rm -rf "$ENVIRONMENT"
    virtualenv "$ENVIRONMENT"
    source "$ENVIRONMENT/bin/activate"
    # workaround to make the virtualenv accept .pth files
    export PYTHONPATH="$PREFIX/lib/python2.7/site-packages:$PYTHONPATH"

    # pyOpenSSL-0.13
    if [ "$pyssl_from" = "pip-install" ] ; then
	echo -e "\\n\\n>> [`date`] pip install pyOpenSSL==0.13"
	pip install pyOpenSSL==0.13
    else
	p=pyOpenSSL-0.13
	echo -e "\\n\\n>> [`date`] building $p"
	test -r $p.tar.gz || wget $wget_opts "$pypi/p/pyOpenSSL/$p.tar.gz"
	rm -rf $p
	tar -xzf $p.tar.gz
	cd $p
	sed -i~ 's/X509_REVOKED_dup/X509_REVOKED_dup_static/' OpenSSL/crypto/crl.c
	python setup.py build_ext "-I$PYTHON_PREFIX/include" "-L$PYTHON_PREFIX/lib"
	python setup.py build
	python setup.py install --prefix="$PREFIX"
	cd ..
	$cleanup && rm -rf $p
    fi

    # LAPACK & BLAS
    if $build_lapack; then
	p=lapack-3.6.0
	echo -e "\\n\\n>> [`date`] building $p"
	test -r $p.tgz || wget $wget_opts http://www.netlib.org/lapack/$p.tgz
	rm -rf $p
	tar -xzf $p.tgz
	cd $p
        # configure: compile with -fPIC, remove -frecoursive, build deprecated functions
	sed "s/ *-frecursive//;s/gfortran/$FC -fPIC -m64/;s/^#MAKEDEPRECATED.*/BUILD_DEPRECATED = Yes/" make.inc.example > make.inc
	make lapack_install lib blaslib
	mkdir -p "$PREFIX/lib"
	cp lib*.a "$PREFIX/lib"
	cp librefblas.a "$PREFIX/lib/libblas.a"
	cd ..
	$cleanup && rm -rf $p
    fi
    
    # NUMPY
    if [ "$numpy_from" = "tarball" ]; then
	p=numpy-1.9.3
	echo -e "\\n\\n>> [`date`] building $p"
	test -r $p.tar.gz || wget $wget_opts https://pypi.python.org/packages/source/n/numpy/$p.tar.gz
	rm -rf $p
	tar -xzf $p.tar.gz 
	cd $p
	python setup.py build --fcompiler=$FC
	python setup.py install --prefix=$PREFIX
	cd ..
	$cleanup && rm -rf $p
    else
	echo -e "\\n\\n>> [`date`] pip install numpy==1.9.3"
	pip install numpy==1.9.3
    fi

    echo -e "\\n\\n>> [`date`] pip install nose"
    pip install nose
    echo -e "\\n\\n>> [`date`] pip install Cython==0.23.2"
    pip install Cython==0.23.2

    # SCIPY
    if [ "$scipy_from" = "pip-install" ] ; then
	echo -e "\\n\\n>> [`date`] pip install scipy==0.16.0"
	pip install scipy==0.16.0
    else
	p=scipy-0.16.0
	echo -e "\\n\\n>> [`date`] building $p"
	if test -d scipy/.git; then
	    cd scipy
	else
	    git clone https://github.com/scipy/scipy.git
	    cd scipy
	    git checkout v0.16.0
	    git cherry-pick 832baa20f0b5d521bcdf4784dda13695b44bb89f
            if [ "$scipy_from" = "git-patched" ] ; then
		wget $wget_opts $atlas/PyCBC_Inspiral/0001-E-H-hack-always-use-dumb-shelve.patch
		wget $wget_opts $atlas/PyCBC_Inspiral/0006-E-H-hack-_dumbdb-open-files-in-binary-mode.patch
		git am 000*.patch
	    fi
	fi
	python setup.py build --fcompiler=$FC
	python setup.py install --prefix=$PREFIX
	cd ..
    fi

    # this test will catch scipy build errors that would not emerge before running pycbc_inspiral
    echo -e "\\n\\n>> [`date`] Testing: python -c 'from scipy.io.wavfile import write as write_wav'"
    python -c 'from scipy.io.wavfile import write as write_wav'
    # python -c 'import scipy; scipy.test(verbose=2);'

    # LIBPQ
    # tried different versions, ended up with 9.2.0
    if $build_libpq; then
	v=9.2.0 # 8.4.22 # 9.3.10
	p=postgresql-$v
	echo -e "\\n\\n>> [`date`] building $p"
	test -r $p.tar.gz || wget $wget_opts "https://ftp.postgresql.org/pub/source/v$v/$p.tar.gz"
	rm -rf $p
	tar -xzf $p.tar.gz
	cd $p
	./configure --without-readline --prefix="$PREFIX"
	cd src/interfaces/libpq
	make
	make install
	mkdir -p "$PREFIX/lib/pkgconfig"
	echo 'prefix=
exec_prefix=${prefix}
includedir=${prefix}/include
libdir=${exec_prefix}/lib
Name: libpq
Description: Postgres client lib
Version: 8.4.22
Cflags: -I${includedir}
Libs: -L${libdir} -lpq' |
	sed "s%^prefix=.*%prefix=$PREFIX%;s/^Version: .*/Version: $v/" > "$PREFIX/lib/pkgconfig/libpq.pc"
	cd ../../../..
	$cleanup && rm -rf $p
    fi

    # GSL
    if $build_gsl; then
	p=gsl-1.16
	echo -e "\\n\\n>> [`date`] building $p"
	test -r $p.tar.gz || wget $wget_opts ftp://ftp.fu-berlin.de/unix/gnu/gsl/$p.tar.gz
	rm -rf $p
	tar -xzf $p.tar.gz
	cd $p
	./configure $shared --enable-static --prefix="$PREFIX"
	make
	make install
	cd ..
	$cleanup && rm -rf $p
    fi

    # FFTW
    p=fftw-3.3.3
    echo -e "\\n\\n>> [`date`] building $p"
    test -r $p.tar.gz || wget $wget_opts http://www.aei.mpg.de/~bema/$p.tar.gz
    rm -rf $p
    tar -xzf $p.tar.gz
    cd $p
    ./configure $shared --enable-static --prefix="$PREFIX" --enable-sse2 $fftw_flags
    make
    make install
    ./configure $shared --enable-static --prefix="$PREFIX" --enable-float --enable-sse $fftw_flags
    make
    make install
    cd ..
    $cleanup && rm -rf $p

    # ZLIB
    p=zlib-1.2.8
    echo -e "\\n\\n>> [`date`] building $p"
    test -r $p.tar.gz || wget $wget_opts http://www.aei.mpg.de/~bema/$p.tar.gz
    rm -rf $p
    tar -xzf $p.tar.gz
    cd $p
    ./configure --prefix=$PREFIX
    make
    make install
    mkdir -p "$PREFIX/lib/pkgconfig"
    echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: ZLIB
Description: zlib Compression Library
Version: 1.2.3
Libs: -L${libdir} -lz
Cflags: -I${includedir}' |
    sed "s%^prefix=.*%prefix=$PREFIX%;s/^Version: .*/Version: $p/;s/^Version: zlib-/Version: /" > "$PREFIX/lib/pkgconfig/zlib.pc"
    cd ..
    $cleanup && rm -rf $p

    # HDF5
    if $build_hdf5; then
	p=hdf5-1.8.12
	echo -e "\\n\\n>> [`date`] building $p"
	test -r $p.tar.gz || wget $wget_opts https://www.hdfgroup.org/ftp/HDF5/releases/hdf5-1.8.12/src/$p.tar.gz
	rm -rf $p
	tar -xzf $p.tar.gz
	cd $p
	./configure $shared --enable-static --prefix="$PREFIX"
	make
	make install
	mkdir -p "$PREFIX/lib/pkgconfig"
	echo 'prefix=
exec_prefix=${prefix}
includedir=${prefix}/include
libdir=${exec_prefix}/lib
Name: hdf5
Description: HDF5
Version: 1.8.12
Requires.private: zlib
Cflags: -I${includedir}
Libs: -L${libdir} -lhdf5' |
	sed "s%^prefix=.*%prefix=$PREFIX%" > "$PREFIX/lib/pkgconfig/hdf5.pc"
	cd ..
	$cleanup && rm -rf $p
    fi

    # FREETYPE
    if $build_freetype; then
	p=freetype-2.3.0
	echo -e "\\n\\n>> [`date`] building $p"
	test -r $p.tar.gz || wget $wget_opts http://download.savannah.gnu.org/releases/freetype/freetype-old/$p.tar.gz
	rm -rf $p
	tar -xzf $p.tar.gz
	cd $p
	./configure $shared --enable-static --prefix="$PREFIX"
	make
	make install
	cd ..
	$cleanup && rm -rf $p
    fi

    echo -e "\\n\\n>> [`date`] pip install --upgrade distribute"
    pip install --upgrade distribute

    if $build_framecpp; then

        # FrameCPP
        p=ldas-tools-2.4.2
        echo -e "\\n\\n>> [`date`] building $p"
        test -r $p.tar.gz || wget $wget_opts http://software.ligo.org/lscsoft/source/$p.tar.gz
        rm -rf $p
        tar -xzf $p.tar.gz
        cd $p
        ./configure --disable-latex --disable-swig --disable-python --disable-tcl --enable-64bit $shared --enable-static --prefix="$PREFIX" # --disable-cxx11
        sed -i~ '/^CXXSTD[A-Z]*FLAGS=/d' ./libraries/ldastoolsal/ldastoolsal*.pc
        make
        make -k install || true
        # cd ..
        # $cleanup && rm -rf $p

    else # build_framecpp

        # LIBFRAME / FrameL
        p=libframe-8.30
        echo -e "\\n\\n>> [`date`] building $p"
        test -r $p.tar.gz || wget $wget_opts http://lappweb.in2p3.fr/virgo/FrameL/$p.tar.gz
        rm -rf $p
        tar -xzf $p.tar.gz
        cd $p
        if test -n "$libframe_debug_level"; then
            sed -i~ "s/^FILE *\\*FrFOut *= *NULL;/#define FrFOut stderr/;
                s/FrDebugLvl *= *[^;]*;/FrDebugLvl = $libframe_debug_level;/" src/FrameL.c
        fi
        # make sure frame files are opened in binary mode
        sed -i~ 's/\([Oo]pen.*"r\)"/\1b"/;' src/FrameL.c # `egrep -r '[Oo]pen.*"r"' .`
        if $build_dlls; then
            for i in src/Makefile*; do
                echo 'libFrame_la_LDFLAGS += -no-undefined' >> $i
            done
        fi
        ./configure $shared --enable-static --prefix="$PREFIX"
        make
        make install
        mkdir -p "$PREFIX/lib/pkgconfig"
        sed "s%^prefix=.*%prefix=$PREFIX%" src/libframe.pc > $PREFIX/lib/pkgconfig/libframe.pc

    fi # build_framecpp

    cd ..
    $cleanup && rm -rf $p

    # METAIO
    p=metaio-8.3.0
    echo -e "\\n\\n>> [`date`] building $p"
    test -r $p.tar.gz || wget $wget_opts https://www.lsc-group.phys.uwm.edu/daswg/download/software/source/$p.tar.gz
    rm -rf $p
    tar -xzf $p.tar.gz
    cd $p
    if $build_dlls; then
	for i in src/Makefile*; do
	    echo 'libmetaio_la_LDFLAGS += -no-undefined' >> $i
	done
    fi
    ./configure $shared --enable-static --prefix="$PREFIX"
    make
    make install
    cd ..
    $cleanup && rm -rf $p

    # SWIG
    if $build_swig; then
	p=swig-3.0.7
	echo -e "\\n\\n>> [`date`] building $p"
	test -r $p.tar.gz || wget $wget_opts "$atlas/tarballs/$p.tar.gz"
	rm -rf $p
	tar -xzf $p.tar.gz
	cd $p
	./configure --prefix=$PREFIX --without-tcl --with-python --without-python3 --without-perl5 --without-octave \
            --without-scilab --without-java --without-javascript --without-gcj --without-android --without-guile \
            --without-mzscheme --without-ruby --without-php --without-ocaml --without-pike --without-chicken \
            --without-csharp --without-lua --without-allegrocl --without-clisp --without-r --without-go --without-d 
	make
	make install
	cd ..
	$cleanup && rm -rf $p
    fi

    if $build_preinst_before_lalsuite; then
	pushd $PYCBC/..
	tar -czf "$SOURCE/pycbc-preinst.tgz" pycbc
        popd
    fi

fi # if pycbc-preinst.tgz

if test -r "$SOURCE/pycbc-preinst-lalsuite.tgz"; then
    :
else

    # LALSUITE
    echo -e "\\n\\n>> [`date`] building lalsuite"
    if test -d lalsuite/.git; then
        cd lalsuite
        git reset --hard HEAD
        git checkout master
        git pull
        if [ ".$lalsuite_branch" != "." ]; then
            git checkout "$lalsuite_branch"
        fi
    elif test ".$lalsuite_branch" = ".eah_cbc"; then
        git clone git://$gitmaster/lalsuite.git
        cd lalsuite
        git checkout -b eah_cbc origin/eah_cbc
    else
        git clone git://versions.ligo.org/lalsuite.git
        cd lalsuite
        if [ ".$lalsuite_branch" != "." ]; then
            git checkout "$lalsuite_branch"
        fi
    fi
    echo -e ">> [`date`] git HEAD: `git log -1 --pretty=oneline --abbrev-commit`"
    sed -i~ s/func__fatal_error/func_fatal_error/ */gnuscripts/ltmain.sh
    if $build_dlls; then
	fgrep -l lib_LTLIBRARIES `find . -name Makefile.am` | while read i; do
	    sed -n 's/.*lib_LTLIBRARIES *= *\(.*\).la/\1_la_LDFLAGS += -no-undefined/p' $i >> $i
	done
	sed -i~ 's/\(swiglal_python_la_LDFLAGS = .*\)$/\1 -no-undefined/;
             s/\(swiglal_python_la_LIBADD = .*\)$/\1 -lpython2.7/;
             s/swiglal_python\.la/libswiglal_python.la/g;
             s/swiglal_python_la/libswiglal_python_la/g;
             s/mv -f swiglal_python/mv -f cygswiglal_python/;' gnuscripts/lalsuite_swig.am
	shared="$shared --enable-win32-dll"
    fi
    if $build_framecpp; then
	shared="$shared --enable-framec --disable-framel"
    fi
    ./00boot
    cd ..
    rm -rf lalsuite-build
    mkdir lalsuite-build
    cd lalsuite-build
    ../lalsuite/configure CPPFLAGS="$lal_cppflags $CPPFLAGS" --disable-gcc-flags $shared --enable-static --prefix="$PREFIX" --disable-silent-rules \
	--enable-swig-python --disable-lalxml --disable-lalpulsar --disable-laldetchar --disable-lalstochastic --disable-lalinference --disable-lalapps
    if $build_dlls; then
	echo '#include "/usr/include/stdlib.h"
extern int setenv(const char *name, const char *value, int overwrite);
extern int unsetenv(const char *name);' > lalsimulation/src/stdlib.h
    fi
    make
    make install
    for i in $PREFIX/etc/*-user-env.sh; do
	source "$i"
    done
    cd ..
    $cleanup && rm -rf lalsuite-build

    pushd $PYCBC/..
    tar -czf "$SOURCE/pycbc-preinst-lalsuite.tgz" pycbc
    popd

fi # if pycbc-preinst.tgz

# PyCBC-GLUE
if [ "$glue_from" = "pip-install" ] ; then
    echo -e "\\n\\n>> [`date`] pip install pycbc-glue==0.9.8"
    pip install pycbc-glue==0.9.8
else
    echo -e "\\n\\n>> [`date`] building pycbc-glue v0.9.8"
    if test -d pycbc-glue/.git; then
        cd pycbc-glue
    else
        git clone https://github.com/ligo-cbc/pycbc-glue.git
        cd pycbc-glue
        git checkout v0.9.8
        # this adds the initialization of *.tp_base,
        # preserving the version for pycbc requirements
        git cherry-pick 16c7eeff3fc2a5cca2c3ea0e259ee5f57abac65c
    fi
    python setup.py install --prefix="$PREFIX"
    cd ..
fi

# h5py
if [ "$h5py_from" = "pip-install" ] ; then
    echo -e "\\n\\n>> [`date`] pip install h5py==2.5.0"
    pip install h5py==2.5.0
else
    echo -e "\\n\\n>> [`date`] building h5py v2.5.0"
    if test -d h5py/.git; then
        cd h5py
    else
        git clone https://github.com/h5py/h5py.git
        cd h5py
        git checkout 2.5.0
    fi
    pip install six==1.9.0 pkgconfig==1.1.0
    python setup.py install --prefix="$PREFIX"
    cd ..
fi

# This is a pretty dirty hack faking psycopg2-2.5.5 to be v2.6
# pegasus-wms is pinned to 2.6 but I couldn't get 2.6 to compile
# see https://github.com/psycopg/psycopg2/issues/305
# psycopgmodule.c _IS_ compiled with -fPIC, but still doesn't link
# tried with newer gcc-4.4.4 and newer binutils to no avail
if [ "$psycopg26_from" = "fake-psycopg255" ]; then
    p=psycopg2-2.5.5
    echo -e "\\n\\n>> [`date`] building $p"
    test -r $p.tar.gz || wget $wget_opts "$pypi/p/psycopg2/$p.tar.gz"
    rm -rf $p
    tar -xzf $p.tar.gz
    cd $p
    sed -i~ 's/2\.5\.5/2.6/' setup.py PKG-INFO
    cd ..
    rm -rf psycopg2-2.6
    mv psycopg2-2.5.5 psycopg2-2.6
    tar -czf psycopg2-2.6f.tar.gz psycopg2-2.6
    cd psycopg2-2.6
# LDFLAGS="-L$PREFIX/lib -fPIC" CPPFLAGS="-I$PREFIX/include" python setup.py build
    python setup.py install --prefix="$PREFIX"
    cd ..
    $cleanup && rm -rf psycopg2-2.6
elif [ "$psycopg26_from" = "pip-install" ]; then
    echo -e "\\n\\n>> [`date`] pip install psycopg2==2.6"
    pip install psycopg2==2.6
fi

# Pegasus
v=4.5.2
p=pegasus-source-$v
if test -r $p-lib-pegasus-python.tgz; then
    :
elif $build_pegasus_source; then
    echo -e "\\n\\n>> [`date`] building $p-lib-pegasus-python.tgz"
    test -r $p.tar.gz || wget $wget_opts "http://download.pegasus.isi.edu/pegasus/$v/$p.tar.gz"
    rm -rf $p
    tar -xzf $p.tar.gz
    if $fake_psycopg26; then
	cp psycopg2-2.6f.tar.gz $p/src/externals/psycopg2-2.6.tar.gz
    fi
    cd $p
    ant dist-python-source
    cd ..
    tar -czf $p-lib-pegasus-python.tgz $p/lib/pegasus/python $p/release-tools $p/build.properties
    $cleanup && rm -rf $p
else
    wget $wget_opts "$atlas/tarballs/$p-lib-pegasus-python.tgz"
fi
echo -e "\\n\\n>> [`date`] building $p"
tar -xzf $p-lib-pegasus-python.tgz
pip install $p/lib/pegasus/python
$cleanup && rm -rf $p

# MPLD
p=mpld3-0.3git
# pip install "https://github.com/ligo-cbc/mpld3/tarball/master#egg=$p"
echo -e "\\n\\n>> [`date`] building $p"
test -r $p.tar.gz || wget $wget_opts -O $p.tar.gz "https://github.com/ligo-cbc/mpld3/tarball/master#egg=$p"
tar -xzf $p.tar.gz
cd ligo-cbc-mpld3-25aee65/
python setup.py install --prefix="$PREFIX"
cd ..
$cleanup && rm -rf ligo-cbc-mpld3-25aee65

# PyInstaller
if echo "$pyinstaller_version" | egrep '^[0-9]\.[0-9]$' > /dev/null; then
    # regular release version, get source tarbal from pypi
    p=PyInstaller-$pyinstaller_version
    echo -e "\\n\\n>> [`date`] building $p"
    test -r $p.tar.gz || wget $wget_opts "https://pypi.python.org/packages/source/P/PyInstaller/$p.tar.gz"
    rm -rf $p
    tar -xzf $p.tar.gz
    cd $p
    if $build_dlls; then
        # patch PyInstaller to find the Python library on Cygwin
	sed -i~ "s|'libpython%d%d.dll'|'libpython%d.%d.dll'|" `find PyInstaller -name bindepend.py`
	cd bootloader
        # build bootloader for Windows
	if $pyinstaller_version | grep '3\.' > /dev/null; then
	    python ./waf distclean all
	else
	    python ./waf configure build install
	fi
	cd ..
    fi
    python setup.py install --prefix="$PREFIX"
    cd ..
    $cleanup && rm -rf $p
else
    p=pyinstaller
    echo -e "\\n\\n>> [`date`] building $p"
    if test -d pyinstaller/.git; then
	cd $p
    else
	git clone git://github.com/$p/$p.git
	cd $p
	if test "$pyinstaller_version" = "v3.0"; then
	    git checkout 3.0
	elif test "$pyinstaller_version" = "9d0e0ad4"; then
	    git checkout $pyinstaller_version
            # patch PyInstaller bootloader to not fork a second process
	    sed -i~ 's/ pid *= *fork()/ pid = 0/' bootloader/common/pyi_utils.c
	else
	    git checkout $pyinstaller_version
	fi
	if $build_dlls; then
            # patch PyInstaller to find the Python library on Cygwin
	    sed -i~ "s|'libpython%d%d.dll'|'libpython%d.%d.dll'|" `find PyInstaller -name bindepend.py`
	fi
    fi

    # build bootloader (in any case: for Cygwin it wasn't precompiled, for Linux it was patched)
    cd bootloader
    if echo "$pyinstaller_version" | grep '3\.' > /dev/null; then
	python ./waf distclean all
    else
	python ./waf configure $pyinstaller_lsb build install
    fi
    cd ..
    python setup.py install --prefix="$PREFIX"
    cd ..
fi

# PyCBC
echo -e "\\n\\n>> [`date`] building pycbc"
if $scratch_pycbc || ! test -d pycbc/.git ; then
    # clone
    rm -rf pycbc
    git clone git://github.com/ligo-cbc/pycbc
    cd pycbc
    git remote rename origin ligo-cbc
    git remote add bema-ligo https://github.com/bema-ligo/pycbc.git
    git remote update
    git branch einsteinathome_testing bema-ligo/einsteinathome_testing
    cd ..
fi
cd pycbc
if test ".$pycbc_branch" = ".HEAD"; then
    :
elif test ".$pycbc_branch" = ".master"; then
    git checkout master
    git pull
else
    # checkout branch from scratch, master must and should exist
    git checkout master
    git branch -D $pycbc_branch
    git remote update
    git checkout -b $pycbc_branch $pycbc_remote/$pycbc_branch
fi
echo -e ">> [`date`] downgrade setuptools"
pip install --upgrade `grep -w ^setuptools requirements.txt`
echo -e ">> [`date`] git HEAD: `git log -1 --pretty=oneline --abbrev-commit`"
pip install .
hooks="$PWD/tools/static"
cd ..
test -r "$PREFIX/etc/pycbc-user-env.sh" && source "$PREFIX/etc/pycbc-user-env.sh"

# clean dist directory
rm -rf "$ENVIRONMENT/dist"
mkdir -p "$ENVIRONMENT/dist"

# on Windows, rebase DLLs
# from https://cygwin.com/ml/cygwin/2009-12/msg00168.html:
# /bin/rebase -d -b 0x61000000 -o 0x20000 -v -T <file with list of dll and so files> > rebase.out
if $build_dlls; then
    echo -e "\\n\\n>> [`date`] Rebasing DLLs"
    find "$ENVIRONMENT" -name \*.dll > "$PREFIX/dlls.txt"
    rebase -d -b 0x61000000 -o 0x20000 -v -T "$PREFIX/dlls.txt"
fi

if $build_wrapper; then
# on Linux, build "progress" and "wrapper"
    echo -e "\\n\\n>> [`date`] Building 'BOINC wrapper', 'progress', 'fstab' and 'fstab_test'"
    if test -d boinc/.git ; then
	cd boinc
	git pull
    else
	# clone
	rm -rf boinc
	git clone git://gitmaster.atlas.aei.uni-hannover.de/einsteinathome/boinc.git
	cd boinc
	git checkout -b eah_wrapper_improvements origin/eah_wrapper_improvements
	./_autosetup
	./configure LDFLAGS=-static-libgcc --disable-client --disable-manager --disable-server --enable-apps --disable-shared
    fi
    echo -e ">> [`date`] git HEAD: `git log -1 --pretty=oneline --abbrev-commit`"
    make
    cp samples/wrapper/wrapper "$ENVIRONMENT/dist/wrapper$appendix"
    cd ..
    gcc -o "$ENVIRONMENT/dist/progress$appendix" $SOURCE/pycbc/tools/einsteinathome/progress.c
    gcc -o "$ENVIRONMENT/dist/fstab" $SOURCE/pycbc/tools/einsteinathome/fstab.c
    gcc -DTEST_WIN32 -o "$ENVIRONMENT/dist/fstab_test" $SOURCE/pycbc/tools/einsteinathome/fstab.c
else
    echo -e "\\n\\n>> [`date`] Building 'progress.exe' and 'fstab.exe'"
    if $build_dlls; then
        x86_64-w64-mingw32-gcc -o "$ENVIRONMENT/dist/progress$appendix.exe" $SOURCE/pycbc/tools/einsteinathome/progress.c
        x86_64-w64-mingw32-gcc -o "$ENVIRONMENT/dist/fstab$appendix.exe" $SOURCE/pycbc/tools/einsteinathome/fstab.c
    else
        gcc -o "$ENVIRONMENT/dist/progress$appendix" $SOURCE/pycbc/tools/einsteinathome/progress.c
        gcc -o "$ENVIRONMENT/dist/fstab$appendix" $SOURCE/pycbc/tools/einsteinathome/fstab.c
    fi
fi

# log environment
echo -e "\\n\\n>> [`date`] ENVIRONMENT ..."
env
echo -e "... ENVIRONMENT"

# TEST
echo -e "\\n\\n>> [`date`] testing local executable"
cd $PREFIX
./bin/pycbc_inspiral --help

# BUNDLE DIR
echo -e "\\n\\n>> [`date`] building pyinstaller spec"
# create spec file
# if the build machine has dbhash & shelve, scipy weave will use bsddb, so make sure these get added
if python -c "import dbhash, shelve" 2>/dev/null; then
    hidden_imports="$hidden_imports --hidden-import=dbhash --hidden-import=shelve"
fi
if $use_pycbc_pyinstaller_hooks; then
    export NOW_BUILDING=NULL
    pyi-makespec --additional-hooks-dir $hooks/hooks $hidden_imports --hidden-import=pkg_resources --onedir ./bin/pycbc_inspiral
else
    # find hidden imports (pycbc CPU modules)
    hidden_imports=`find $PREFIX/lib/python2.7/site-packages/pycbc/ -name '*_cpu.py' | sed 's%.*/site-packages/%%;s%\.py$%%;s%/%.%g;s%^% --hidden-import=%' | tr -d '\012'`
    pyi-makespec $hidden_imports --hidden-import=scipy.linalg.cython_blas --hidden-import=scipy.linalg.cython_lapack --hidden-import=pkg_resources --onedir ./bin/pycbc_inspiral
fi
# patch spec file to add "-v" to python interpreter options
if $verbose_pyinstalled_python; then
    sed -i~ 's%exe = EXE(pyz,%options = [ ("v", None, "OPTION"), ("W error", None, "OPTION") ]\
exe = EXE(pyz, options,%' pycbc_inspiral.spec
fi
echo -e "\\n\\n>> [`date`] running pyinstaller"
pyinstaller pycbc_inspiral.spec

cd dist/pycbc_inspiral

# fix libgomp
if test -r /usr/bin/cyggomp-1.dll; then
    cp /usr/bin/cyggomp-1.dll .
else
    libgomp=`gcc -print-file-name=libgomp.so.1`
    if test "$libgomp" != "libgomp.so.1"; then
        cp "$libgomp" .
    fi
fi

# create (empty) "Tcl/Tk data directories"
# I really don't know why the application needs to crash without these
mkdir -p tcl tk

# OSX doesn't have a GNU error C extension, so drop an "error.h" header
# with a fake 'error' function somewhere for scipy wave to pick it up
if test ".$appendix" = "._OSX64"; then
    echo '#define error(status, errnum, errstr, ...) fprintf(stderr,"pycbc_inspiral: %d:%d:" errstr, status, errnum, ##__VA_ARGS__)' > scipy/weave/error.h
fi

# TEST BUNDLE
echo -e "\\n\\n>> [`date`] testing"
./pycbc_inspiral --help
cd ..

# build zip file from dir
zip -r pycbc_inspiral$appendix.zip pycbc_inspiral

# if the executable is "pycbc_inspiral.exe", add a "XML soft link" "pycbc_inspiral" to the bundle for the wrapper
if $build_dlls; then
    mkdir -p tmp/pycbc_inspiral
    echo '<soft_link>pycbc_inspiral/pycbc_inspiral.exe<soft_link/>' > tmp/pycbc_inspiral/pycbc_inspiral
    cd tmp
    zip ../pycbc_inspiral$appendix.zip pycbc_inspiral/pycbc_inspiral
fi

# run 10min self-test, build wave cache
echo -e "\\n\\n>> [`date`] running analysis"
cd "$SOURCE"
mkdir -p test
cd test

p="H-H1_LOSC_4_V1-1126257414-4096.gwf"
md5="a7d5cbd6ef395e8a79ef29228076d38d"
if check_md5 "$p" "$md5"; then
    rm -f "$p"
    wget $wget_opts "$albert/$p"
    if check_md5 "$p" "$md5"; then
        echo "can't download $p - md5 mismatch"
        exit 1
    fi
fi
f="$PWD/$p"

p="SEOBNRv2ChirpTimeSS.dat"
md5="7b7dbadacc3f565fb2c8e6971df2ab74"
if check_md5 "$p" "$md5"; then
    rm -f "$p"
    wget $wget_opts "$albert/$p"
    if check_md5 "$p" "$md5"; then
        echo "can't download $p - md5 mismatch"
        exit 1
    fi
fi

#fb5ec108c69f9e424813de104731370c  H1L1-PREGEN_TMPLTBANK_SPLITBANK_BANK16-1126051217-3331800-short2k.xml.gz
p="H1L1-SBANK_FOR_GW150914.xml.gz"
md5="401324352d30888a5df2e5cc65035b17"
if check_md5 "$p" "$md5"; then
    rm -f "$p"
    wget $wget_opts "$albert/$p"
    if check_md5 "$p" "$md5"; then
        echo "can't download $p - md5 mismatch"
        exit 1
    fi
fi

if $build_framecpp; then
    export LAL_FRAME_LIBRARY=FrameC
else
    export LAL_FRAME_LIBRARY=FrameL
fi

LAL_DATA_PATH="." \
  NO_TMPDIR=1 \
  INITIAL_LOG_LEVEL=10 \
  LEVEL2_CACHE_SIZE=8192 \
  WEAVE_FLAGS='-O3 -march=core2 -w' \
  "$ENVIRONMENT/dist/pycbc_inspiral/pycbc_inspiral" \
  --fixed-weave-cache \
  --segment-end-pad 16 \
  --cluster-method window \
  --low-frequency-cutoff 30 \
  --pad-data 8 \
  --cluster-window 1 \
  --sample-rate 4096 \
  --injection-window 4.5 \
  --segment-start-pad 112 \
  --psd-segment-stride 8 \
  --approximant IMRPhenomD \
  --psd-inverse-length 16 \
  --filter-inj-only \
  --psd-segment-length 16 \
  --snr-threshold 5.5 \
  --segment-length 256 \
  --autogating-width 0.25 \
  --autogating-threshold 100 \
  --autogating-cluster 0.5 \
  --autogating-taper 0.25 \
  --newsnr-threshold 5 \
  --psd-estimation median \
  --strain-high-pass 20 \
  --order -1 \
  --chisq-bins "1.75*(get_freq('fSEOBNRv2Peak',params.mass1,params.mass2,params.spin1z,params.spin2z)-60.)**0.5" \
  --channel-name H1:LOSC-STRAIN \
  --gps-start-time 1126259078 \
  --gps-end-time 1126259846 \
  --output H1-INSPIRAL-OUT.hdf \
  --frame-files "$f" \
  --bank-file "$p" \
  --verbose 2>&1

# test for GW150914
echo -e "\\n\\n>> [`date`] test for GW150914"
python $SOURCE/pycbc/tools/einsteinathome/check_GW150914_detection.py H1-INSPIRAL-OUT.hdf

# zip weave cache
echo -e "\\n\\n>> [`date`] zipping weave cache"
cache="$ENVIRONMENT/dist/pythoncompiled$appendix.zip"
rm -f "$cache"
zip -r "$cache" pycbc_inspiral SEOBNRv2ChirpTimeSS.dat

echo -e "\\n\\n>> [`date`] Success $0"