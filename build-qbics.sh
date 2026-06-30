#!/bin/bash

########################################################################
#                                                                      #
#   Run: ./build.sh         to build Qbics.                            #
#   Run: ./build.sh mkl     to build Qbics with MKL support.           #
#   Run: ./build.sh clean   to clean cache files for rebuilding.       #
#   Run: ./build.sh package to prepare a package of Qbics.             #
#                                                                      #
########################################################################
numCores=64                            # Number of cores to compile.
export CC=gcc FC=gfortran              # Compilers.
useMKL=0
if test $1 = "mkl"; then
    source /opt/intel/oneapi/setvars.sh
    useMKL=1
fi

########################################################################
#                                                                      #
#   Do NOT change the following unless you                             #
#   ABSOLUTELY know what you are doing.                                #
#                                                                      #
########################################################################
rootDir=`pwd`
thirdDir=${rootDir}/third-party
if test $1 = "clean"; then
    rm ${thirdDir}/libxc-6.2.2 ${thirdDir}/libxc-6.2.2-src -rf
    rm ${thirdDir}/fftw-3.3.10 ${thirdDir}/fftw-3.3.10-src -rf
    rm ${thirdDir}/plumed-2.9.2 ${thirdDir}/plumed-2.9.2-src -rf
    rm ${thirdDir}/dftd3-0.9 ${thirdDir}/dftd3-0.9-src -rf
    rm ${thirdDir}/OpenBLAS-0.3.28 ${thirdDir}/OpenBLAS-0.3.28-src -rf
    rm ${thirdDir}/xtb-6.5.0 ${thirdDir}/xtb-6.5.0-src -rf
    rm ${thirdDir}/dl-find ${thirdDir}/dl-find-src -rf
    rm ${thirdDir}/hdf5-hdf5_1.14.6 ${thirdDir}/hdf5-hdf5_1.14.6-src -rf
    rm qbics-Release/* -rf
    cd qbics-source
    make clean 
    cd ../
    echo -e "\nQbics cache cleared. You can rebuild it now.\n"
    exit 
fi
if test $1 = "package"; then
    mkdir qbics-source-env
    cp -r qbics-source qbics-source-env/
    cp -r qbics-Release qbics-source-env/
    cp -r ${thirdDir} qbics-source-env/
    cp build-qbics.sh qbics-source-env/
    cd qbics-source-env/; ./build-qbics.sh clean; tar -cvzf qbics-source.tar.gz qbics-source; cd ../
    mv qbics-source-env/qbics-source.tar.gz .    
    tar -cvzf qbics-source-env.tar.gz qbics-source-env
    rm qbics-source-env -rf
    echo -e "\nQbics source code and third-party libraries are packaged in qbics-source-env.tar.gz.\n"
    echo -e "\nQbics lean source code is packaged in qbics-source.tar.gz.\n"
    exit
fi

#####################################################################
echo "Qbics compilation begins!"
echo ""
echo ${numCores} "CPU cores will be used for building."
echo ""

#####################################################################
boostVer=1.78.0
eigenVer=3.4.0
echo "1. boost is already available. Version:" ${boostVer}
echo "2. eigen is already available. Version:" ${eigenVer}
echo ""

#####################################################################
libxcVer=6.2.2
echo "3. Build libxc. Version:" ${libxcVer}
cd ${thirdDir}
tar -xvf libxc-6.2.2-src.tar
cd libxc-6.2.2-src
autoreconf -i || exit
./configure --prefix=${thirdDir}/libxc-6.2.2 || exit
make CFLAGS="-std=c99 -O2" -j${numCores} || exit
make install || exit
cd ../../
echo "libxc is built successfully!"
echo ""

#####################################################################
fftw3Ver=3.3.10
echo "4. Build fftw3. Version:" ${fftw3Ver}
cd ${thirdDir}
tar -xvf fftw-3.3.10-src.tar
cd fftw-3.3.10-src
./configure --prefix=${thirdDir}/fftw-3.3.10 --enable-openmp || exit
make -j${numCores} || exit
make install || exit
cd ../../
echo "fftw3 is built successfully!"
echo ""

#####################################################################
plumedVer=2.9.2
echo "5. Build plumed. Version:" ${plumedVer}
cd ${thirdDir}
tar -xvf plumed-2.9.2-src.tar
cd plumed-2.9.2-src 
./configure --prefix=${thirdDir}/plumed-2.9.2 --disable-mpi --disable-external-lapack --disable-external-blas || exit
make -j${numCores} || exit
make install || exit
cd ../../
echo "plumed is built successfully!"
echo ""

#####################################################################
dftd3Ver=0.9
echo "6. Build DFTD3-lib. Version:" ${dftd3Ver}
cd ${thirdDir}
tar -xvf dftd3-0.9-src.tar
cd dftd3-0.9-src
make -j${numCores} FC=gfortran || exit
mkdir ../dftd3-0.9
cp libdftd3.a dftd3_api.mod ../dftd3-0.9
cd ../../
echo "DFTD3-lib is built successfully!"
echo ""

#####################################################################
openblasVer=0.3.28
echo "7. Build OpenBLAS. Version:" ${openblasVer}
cd ${thirdDir}
tar -xvf OpenBLAS-0.3.28-src.tar
cd OpenBLAS-0.3.28-src
make -j${numCores} || exit
make install PREFIX=../OpenBLAS-0.3.28 || exit
cd ../../
echo "OpenBLAS is built successfully!"
echo ""

#####################################################################
xtbVer=6.5.0
echo "8. Build xtb. Version:" ${xtbVer}
cd ${thirdDir}
tar -xvf xtb-6.5.0-src.tar
cd xtb-6.5.0-src
if test $useMKL = 0; then
    cmake -B build -DCMAKE_BUILD_TYPE=Release -Dlapack=openblas -DLAPACK_LIBRARIES=${thirdDir}/OpenBLAS-0.3.28/lib/libopenblas.a -DBLAS_LIBRARIES=${thirdDir}/OpenBLAS-0.3.28/lib/libopenblas.a   -DCMAKE_INSTALL_PREFIX:PATH=${thirdDir}/xtb-6.5.0 || exit
else
    cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=${thirdDir}/xtb-6.5.0 || exit
fi
make install -C build -j${numCores} || exit
mv ${thirdDir}/xtb-6.5.0/lib64  ${thirdDir}/xtb-6.5.0/lib # In some cases the library name becomes lib64, so it is forced to change.
cd ../../
echo "xtb is built successfully!"
echo ""

#####################################################################
echo "9. Build dl-find."
cd ${thirdDir}
tar -xvf dl-find-src.tar
cd dl-find-src
make -f Makefile.qbics || exit
cd ../../
echo "dl-find is built successfully!"
echo ""

#####################################################################
hdf5Ver=1.14.6
echo "10. Build HDF5. Version:" ${hdf5Ver}
cd ${thirdDir}
tar -xvzf hdf5-hdf5_1.14.6-src.tar.gz
cd hdf5-hdf5_1.14.6-src
./configure --enable-cxx --prefix=${thirdDir}/hdf5-hdf5_1.14.6 || exit
make install -j${numCores} || exit
cd ../../
echo "HDF5 is built successfully!"
echo ""

#####################################################################
echo "11. Build Qbics."
cd qbics-source
if test $useMKL = 0; then
    make linux-cpu -j${numCores} || exit
else
    make linux-cpu eigen_mkl=1 -j${numCores} || exit    
fi
cp ${thirdDir}/plumed-2.9.2 bin -rf
cp bin/* ../qbics-Release -rf
cd ..
tar -cvzf qbics.tar.gz qbics-Release
echo "Qbics is built successfully!"
echo ""

#####################################################################
echo "All compiled third-party libraries are in:" ${thirdDir}
echo "You can use them for other purposes."
echo ""
echo "All Qbics files are in:" ${rootDir}/qbics-Release
echo "You can copy this directory to any path."
echo ""
echo "Now, try to run:"
echo "   cd test"
echo "   ../Release/qbics-linux-cpu dft.inp -n 2 > dft.out"
echo "to test Qbics."

