#!/bin/bash

# script to build PyCBC suite on Debian Etch and Windows Cygwin

# FIXME/todo:
#
# A couple of quick & dirty hacks for the Cygwin build need to be made properly:
#
# - PyInstaller: "return /usr/bin/libpython2.7.dll when no other Python lib was found"
#   this is pretty dirty & hardcoded. At least check whether the library is actually there.
#   Even better, fix the query (currently PyInstaller looks for a libpython.2.7.dll)
#
# - PyInstaller (Linux): pass SIGSTOP & SIGCONT to child process (or don't create any)
#
# - pycbc-glue: ".tp_base = NULL"
#   in Python on Windows, &PyTuple_Type is not known at compile time, thus I get
#   "initializer is not constant. Solution would be to initalize at run time.

set -e

echo -e "\\n\\n>> [`date`] Start $0"

if [ ".$DEBUG" = "." ]; then
  cleanup=true
else
  cleanup=false
fi

if test "v`cat /etc/debian_version 2>/dev/null`" = "v4.0"; then
  echo -e "\\n\\n>> [`date`] Using Debian 4.0 (etch) settings"
  shared="--enable-shared"
  build_dlls=false
  build_ssl=true
  build_pyssl=true
  build_python=false
  build_lapack=true
  compile_numpy=false
  patch_scipy=false
  compile_scipy=true
  build_hdf5=true
  build_freetype=true
  build_libpq=false
  build_gsl=true
  build_swig=true
  compile_pycbc_glue=false
  fake_psycopg26=true
  build_pegasus_source=true
  build_preinst_before_lalsuite=false
  pyinstaller_version=9d0e0ad4 # 9d0e0ad4, v2.1, v3.0 or v3.1 -> git, 2.1 or 3.0 -> pypi 
  use_pycbc_pyinstaller_hooks=true
  verbose_pyinstalled_python=false
else
  echo -e "\\n\\n>> [`date`] Using Cygwin settings"
  export CPPFLAGS="$CPPFLAGS -D_WIN32"
  shared="--enable-shared"
  build_dlls=true
  build_ssl=false
  build_pyssl=true
  build_python=false
  build_lapack=true
  compile_numpy=true
  patch_scipy=false
  compile_scipy=true
  build_hdf5=false
  build_freetype=false
  build_libpq=false
  build_gsl=false
  build_swig=false
  compile_pycbc_glue=true
  fake_psycopg26=true
  build_pegasus_source=false
  build_preinst_before_lalsuite=true
  pyinstaller_version=9d0e0ad4 # 9d0e0ad4, v2.1, v3.0 or v3.1 -> git, 2.1 or 3.0 -> pypi 
  use_pycbc_pyinstaller_hooks=true
  verbose_pyinstalled_python=false
fi

# compilation environment
PYCBC="$PWD/pycbc"
SOURCE="$PYCBC/source"
PYTHON_PREFIX="$PYCBC"
ENVIRONMENT="$PYCBC/environment"
PREFIX="$ENVIRONMENT"
PATH="$PREFIX/bin:$PYTHON_PREFIX/bin:$PATH"
export FC=gfortran
libgfortran="`$FC -print-file-name=libgfortran.so|sed 's%/[^/]*$%%'`"
export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/bin:$PYTHON_PREFIX/lib:$libgfortran:/usr/local/lib:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PYTHON_PREFIX/lib/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
export LIBS="$LIBS -lgfortran"

# log compilation environment
echo "export PATH='$PATH'"
echo "export LD_LIBRARY_PATH='$LD_LIBRARY_PATH'"
echo "export PKG_CONFIG_PATH='$PKG_CONFIG_PATH'"

#export CPPFLAGS="-I$PREFIX/include"
#export LDFLAGS="-L$PREFIX/lib -L$libgfortran"
#export LDFLAGS="-L$libgfortran $LDFLAGS"
# -static-libgfortran

# URL abbrevations
pypi="http://pypi.python.org/packages/source"
gitmaster="gitmaster.atlas.aei.uni-hannover.de/einsteinathome"
atlas="https://www.atlas.aei.uni-hannover.de/~bema"

# circumvent old certificate chains
export GIT_SSL_NO_VERIFY=true
wget_opts="-c --passive-ftp --no-check-certificate"
pip_install="install --trusted-host pypi.python.org --trusted-host github.com"

# use precompiles scipy, lalsuite etc. if available
if test -r pycbc-preinst.tgz -o -r pycbc-preinst-lalsuite.tgz; then

  rm -rf pycbc
  if test -r pycbc-preinst-lalsuite.tgz; then
    echo -e "\\n\\n>> [`date`] using pycbc-preinst-lalsuite.tgz"
    tar -xzf pycbc-preinst-lalsuite.tgz
  else
    echo -e "\\n\\n>> [`date`] using pycbc-preinst.tgz"
    tar -xzf pycbc-preinst.tgz
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

  mkdir -p "$SOURCE"
  cd "$SOURCE"

  if test -d lalsuite/.git; then
    :
  else
    git clone git://$gitmaster/lalsuite.git
    cd lalsuite
    git checkout -b eah_cbc origin/eah_cbc
    cd ..
  fi

  # OpenSSL
  if $build_ssl; then
    # p=openssl-1.0.2e # compile error on pyOpenSSL 0.13:
    # pycbc/include/openssl/x509.h:751: note: previous declaration X509_REVOKED_ was here
    p=openssl-1.0.1p
    echo -e "\\n\\n>> [`date`] building $p"
    test -r $p.tar.gz || wget $wget_opts http://www.openssl.org/source/$p.tar.gz
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
    pip $pip_install virtualenv
  fi

  # set up virtual environment
  unset PYTHONPATH
  rm -rf "$ENVIRONMENT"
  virtualenv "$ENVIRONMENT"
  source "$ENVIRONMENT/bin/activate"
  # workaround to make the virtualenv accept .pth files
  export PYTHONPATH="$PREFIX/lib/python2.7/site-packages:$PYTHONPATH"

  # pyOpenSSL-0.13
  if $build_pyssl; then
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
  else
    echo -e "\\n\\n>> [`date`] pip install pyOpenSSL==0.13"
    pip $pip_install pyOpenSSL==0.13
  fi

  # http://sourceforge.net/projects/math-atlas/files/Stable/3.10.2/atlas3.10.2.tar.bz2

  # LAPACK & BLAS
  if $build_lapack; then
    p=lapack-3.6.0
    echo -e "\\n\\n>> [`date`] building $p"
    test -r $p.tgz || wget $wget_opts http://www.netlib.org/lapack/$p.tgz
    rm -rf $p
    tar -xzf $p.tgz
    cd $p
    # configure: compile with -fPIC, remove -frecoursive, build deprecated functions
    sed "s/ *-frecursive//;s/gfortran/$FC -fPIC/;s/^#MAKEDEPRECATED.*/BUILD_DEPRECATED = Yes/" make.inc.example > make.inc
    make lapack_install lib blaslib
    mkdir -p "$PREFIX/lib"
    cp lib*.a "$PREFIX/lib"
    cp librefblas.a "$PREFIX/lib/libblas.a"
    cd ..
    $cleanup && rm -rf $p
  fi
  
  # NUMPY
  if $compile_numpy; then
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
    pip $pip_install numpy==1.9.3
  fi

  echo -e "\\n\\n>> [`date`] pip install nose"
  pip $pip_install nose
  echo -e "\\n\\n>> [`date`] pip install Cython==0.23.2"
  pip $pip_install Cython==0.23.2

  # SCIPY
  if $compile_scipy; then
    p=scipy-0.16.0
    echo -e "\\n\\n>> [`date`] building $p"
    if test -d scipy/.git; then
      cd scipy
    else
      git clone https://github.com/scipy/scipy.git
      cd scipy
      git checkout v0.16.0
      git cherry-pick 832baa20f0b5d521bcdf4784dda13695b44bb89f
      if $patch_scipy; then
        wget $wget_opts $atlas/PyCBC_Inspiral/0001-E-H-hack-always-use-dumb-shelve.patch
        wget $wget_opts $atlas/PyCBC_Inspiral/0006-E-H-hack-_dumbdb-open-files-in-binary-mode.patch
        git am 000*.patch
      fi
    fi
    python setup.py build --fcompiler=$FC
    python setup.py install --prefix=$PREFIX
    cd ..
  else
    echo -e "\\n\\n>> [`date`] pip install scipy==0.16.0"
    pip $pip_install scipy==0.16.0
  fi

  # this test will catch scipy build errors that would not emerge before running pycbc_inspiral
  echo -e "\\n\\n>> [`date`] Testing: python -c 'from scipy.io.wavfile import write as write_wav'"
  python -c 'from scipy.io.wavfile import write as write_wav'
# python -c 'import scipy; scipy.test(verbose=2);'

  # LIBPQ
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
  ./configure $shared --enable-static --prefix="$PREFIX"
  make
  make install
  ./configure $shared --enable-static --prefix="$PREFIX" --enable-float
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
  pip $pip_install --upgrade distribute

  # LIBFRAME
  p=libframe-8.21
  echo -e "\\n\\n>> [`date`] building $p"
  test -r $p.tar.gz || wget $wget_opts http://lappweb.in2p3.fr/virgo/FrameL/$p.tar.gz
  rm -rf $p
  tar -xzf $p.tar.gz
  cd $p
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
  tar -czf pycbc-preinst.tgz pycbc
  popd
fi

fi # if pycbc-preinst.tgz

if test -r $PYCBC/../pycbc-preinst-lalsuite.tgz; then
  :
else

  # LALSUITE
  echo -e "\\n\\n>> [`date`] building lalsuite"
  cd lalsuite
  git reset --hard HEAD
  echo -e "\\n\\n>> [`date`] git HEAD: `git log -1 --pretty=oneline --abbrev-commit`"
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
  ./00boot
  cd ..
  rm -rf lalsuite-build
  mkdir lalsuite-build
  cd lalsuite-build
  ../lalsuite/configure --disable-gcc-flags $shared --enable-static --enable-swig-python --prefix="$PREFIX" --disable-silent-rules \
      --disable-lalxml --disable-lalpulsar --disable-laldetchar --disable-lalstochastic --disable-lalinference --disable-lalapps
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
  echo -e "\\n\\n>> [`date`] building PyLAL"
  cd lalsuite/pylal
  python setup.py install --prefix="$PREFIX"
#  echo -e "\\n\\n>> [`date`] building GLUE"
#  cd ../glue
#  python setup.py install --prefix="$PREFIX"
  cd ../..
  test -r "$PREFIX/etc/pylal-user-env.sh" && source "$PREFIX/etc/pylal-user-env.sh"
  test -r "$PREFIX/etc/glue-user-env.sh" && source "$PREFIX/etc/glue-user-env.sh"

  pushd $PYCBC/..
  tar -czf pycbc-preinst-lalsuite.tgz pycbc
  popd

fi # if pycbc-preinst.tgz

echo 'Flask==0.10
Flask-Cache==0.13.1
Flask-SQLAlchemy==0.16
Jinja2==2.7
MarkupSafe==0.18
MySQL-python==1.2.5
SQLAlchemy==0.8.0
WTForms==1.0.3
Werkzeug==0.9.3
boto==2.5.2
itsdangerous==0.21
pam==0.1.4
requests==1.2.3
decorator==4.0.4
pycbc-pylal==0.9.5
pyRXP==2.1.0
nose==1.3.7
pkgconfig==1.1.0
six==1.9.0
linecache2==1.0.0
traceback2==1.4.0
unittest2==1.1.0
cycler==0.9.0
python-dateutil==2.4.2
Babel==2.1.1
M2Crypto==0.22.3
Mako==1.0.2
Pillow==2.9.0
Pygments==2.0.2
Sphinx==1.3.1
alabaster==0.7.6
argparse==1.3.0
docutils==0.12
funcsigs==0.4
matplotlib==1.4.3
mock==1.3.0
numpydoc==0.5
pbr==1.8.0
pyparsing==2.0.3
python-cjson==1.1.0
pytz==2015.6
snowballstemmer==1.2.0
sphinx-rtd-theme==0.1.9
sphinxcontrib-programoutput==0.8' > requirements.txt
pip $pip_install -r requirements.txt
# don't downgrade to setuptools==18.2 here yet

if $compile_pycbc_glue; then
  p=pycbc-glue-0.9.6
  echo -e "\\n\\n>> [`date`] building $p"
  test -r $p.tar.gz || wget $wget_opts "$pypi/p/pycbc-glue/$p.tar.gz"
  rm -rf $p
  tar -xzf $p.tar.gz
  cd $p
  # This is pretty ugly just to get things compiled. It won't work when used.
  # This avoids error: initializer element is not constant
  sed -i~ 's/\.tp_base = &PyTuple_Type/.tp_base = NULL/' src/segments/segment.c
  sed -i~ 's/\.tp_base = &PyList_Type/.tp_base = NULL/' src/segments/segmentlist.c
  python setup.py install --prefix="$PREFIX"
  cd ..
  $cleanup && rm -rf $p
else
  echo -e "\\n\\n>> [`date`] pip install pycbc-glue==0.9.6"
  pip $pip_install pycbc-glue==0.9.6
fi

echo -e "\\n\\n>> [`date`] pip install h5py==2.5.0"
pip $pip_install h5py==2.5.0

# This is a pretty dirty hack faking psycopg2-2.5.5 to be v2.6
# pegasus-wms is pinned to it but I couldn't get 2.6 to compile
# see https://github.com/psycopg/psycopg2/issues/305
# psycopgmodule.c _IS_ compiled with -fPIC, but still doesn't link
# tried with newer gcc-4.4.4 and newer binutils
if $fake_psycopg26; then
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
else
  echo -e "\\n\\n>> [`date`] pip install psycopg2==2.6"
  pip $pip_install psycopg2==2.6
fi

# PEGASUS
v=4.5.2
p=pegasus-source-$v
if test -r $p-lib-pegasus-python.tgz; then
  :
elif $build_pegasus_source; then
  test ".$LC_CTYPE" = ".UTF-8" && export LC_ALL=en_US.UTF-8
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
  wget $wget_opts http://www.atlas.aei.uni-hannover.de/~bema/tarballs/$p-lib-pegasus-python.tgz
fi
echo -e "\\n\\n>> [`date`] building $p"
tar -xzf $p-lib-pegasus-python.tgz
pushd $p/lib/pegasus/python/
# echo -e "\\n\\n>> [`date`] installing dependencies for $p"
# pip $pip_install -r pegasus_wms.egg-info/requires.txt
python setup.py install --prefix="$PREFIX"
popd
$cleanup && rm -rf $p

# MPLD
p=mpld3-0.3git
# pip $pip_install "https://github.com/ligo-cbc/mpld3/tarball/master#egg=$p"
echo -e "\\n\\n>> [`date`] building $p"
test -r $p.tar.gz || wget $wget_opts -O $p.tar.gz "https://github.com/ligo-cbc/mpld3/tarball/master#egg=$p"
tar -xzf $p.tar.gz
cd ligo-cbc-mpld3-25aee65/
python setup.py install --prefix="$PREFIX"
cd ..
$cleanup && rm -rf ligo-cbc-mpld3-25aee65

# PYINSTALLER
pyinstaller_version=9d0e0ad4 # 9d0e0ad4, v2.1, v3.1 or v3.0 -> git, 2.1 or 3.0 -> pypi 
if $pyinstaller_version | egrep '^[0-9]\.[0-9]$' > /dev/null; then
  p=PyInstaller-$pyinstaller_version
  echo -e "\\n\\n>> [`date`] building $p"
  test -r $p.tar.gz || wget $wget_opts "https://pypi.python.org/packages/source/P/PyInstaller/$p.tar.gz"
  rm -rf $p
  tar -xzf $p.tar.gz
  cd $p
  if $build_dlls; then
    # patch PyInstaller to return /usr/bin/libpython2.7.dll when no other Python lib was found
    sed -i~ 's%# Python library NOT found. Return just None.%return "/usr/bin/libpython2.7.dll"%' `find PyInstaller -name bindepend.py`
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
  echo -e "\\n\\n>> [`date`] building pyinstaller"
  if test -d pyinstaller/.git; then
    cd pyinstaller
  else
    git clone git://github.com/pyinstaller/pyinstaller.git
    cd pyinstaller
    if test "$pyinstaller_version" = "v3.0"; then
      git checkout 3.0
    elif test "$pyinstaller_version" = "9d0e0ad4"; then
      git checkout $pyinstaller_version
      patch=0001-PyInstaller-bootloader-pass-SIGSTOP-and-SIGCONT-to-t.patch
      wget $wget_opts "https://$gitmaster/pycbc/blobs/raw/einsteinathome_hacks/tools/einsteinathome/$patch"
      git am "$patch"
    else
      git checkout $pyinstaller_version
    fi
    if $build_dlls; then
      # patch PyInstaller to return /usr/bin/libpython2.7.dll when no other Python lib was found
      sed -i~ 's%# Python library NOT found. Return just None.%return "/usr/bin/libpython2.7.dll"%' `find PyInstaller -name bindepend.py`
    fi
  fi

# build bootloader for Windows
if $build_dlls; then
    cd bootloader
    if $pyinstaller_version | grep '3\.' > /dev/null; then
      python ./waf distclean all
    else
      python ./waf configure build install
    fi
    cd ..
  fi
  python setup.py install --prefix="$PREFIX"
  cd ..
fi

# PYCBC
echo -e "\\n\\n>> [`date`] downgrade to setuptools==18.2"
pip $pip_install --upgrade setuptools==18.2
echo -e "\\n\\n>> [`date`] building pycbc"
if test -d pycbc/.git; then
  cd pycbc
else
  rm -rf pycbc
  # git clone git://github.com/ligo-cbc/pycbc
  git clone git://$gitmaster/pycbc.git
  cd pycbc
  git checkout -b einsteinathome origin/einsteinathome
fi
pip install .
hooks="$PWD/tools/static"
cd ..
test -r "$PREFIX/etc/pycbc-user-env.sh" && source "$PREFIX/etc/pycbc-user-env.sh"

# log environment
echo -e "\\n\\n>> [`date`] ENVIRONMENT ..."
env
echo -e "... ENVIRONMENT"

# rebase DLLs
# from https://cygwin.com/ml/cygwin/2009-12/msg00168.html:
# /bin/rebase -d -b 0x61000000 -o 0x20000 -v -T <file with list of dll and so files> > rebase.out
if $build_dlls; then
  find "$ENVIRONMENT" -name \*.dll > "$PREFIX/dlls.txt"
  rebase -d -b 0x61000000 -o 0x20000 -v -T "$PREFIX/dlls.txt"
fi

# TEST
echo -e "\\n\\n>> [`date`] testing local executable"
cd $PREFIX
./bin/pycbc_inspiral --help

# BUNDLE DIR
echo -e "\\n\\n>> [`date`] building pyinstaller spec"
rm -rf dist
# create spec file
# if the build machine has dbhash & shelve, scipy weave will use bsddb, so add these to the bundle
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
    cp `gcc -print-file-name=libgomp.so.1` .
fi

# TEST BUNDLE
echo -e "\\n\\n>> [`date`] testing"
./pycbc_inspiral --help
cd ..

# build zip file from dir
zip -r pycbc_inspiral.zip pycbc_inspiral

# if the executable is "pycbc_inspiral.exe", add a "XML soft link" "pycbc_inspiral" to the bundle for the wrapper
if $build_dlls; then
    mkdir -p tmp/pycbc_inspiral
    echo '<soft_link>pycbc_inspiral/pycbc_inspiral.exe<soft_link/>' > tmp/pycbc_inspiral/pycbc_inspiral
    cd tmp
    zip ../pycbc_inspiral.zip pycbc_inspiral/pycbc_inspiral
fi

echo -e "\\n\\n>> [`date`] Success $0"
