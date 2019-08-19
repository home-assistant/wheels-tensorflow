ARG BUILD_FROM
FROM $BUILD_FROM

ARG BUILD_ARCH
ARG TENSORFLOW_VERSION=1.13.2
ARG BAZEL_VERSION=0.21.0
ARG HDF5_VERSION=1.8.21
ENV JAVA_HOME="/usr/lib/jvm/java-1.8-openjdk"

WORKDIR /usr/src
RUN apk add --no-cache \
        freetype libpng libjpeg-turbo musl \
    && apk add --no-cache --virtual=.build-dependencies \
        git cmake build-base curl freetype-dev g++ libjpeg-turbo-dev libpng-dev \
        linux-headers make openjdk11 zip patch \
        autoconf automake libtool file sed \
    \
    && curl -SL https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.8/hdf5-$HDF5_VERSION/src/hdf5-$HDF5_VERSION.tar.gz | tar xzf - \
    && cd /usr/src/hdf5-$HDF5_VERSION \
    && ./configure --prefix=/usr/local \
    && make \
    && make install \
    \
    && cd /usr/src \
    && curl -SLO https://github.com/bazelbuild/bazel/releases/download/$BAZEL_VERSION/bazel-$BAZEL_VERSION-dist.zip \
    && mkdir bazel-$BAZEL_VERSION \
    && unzip -qd bazel-$BAZEL_VERSION bazel-$BAZEL_VERSION-dist.zip \
    && cd /usr/src/bazel-$BAZEL_VERSION \
    && EXTRA_BAZEL_ARGS=--host_javabase=@local_jdk//:jdk ./compile.sh \
    && cp -p output/bazel /usr/bin/ \
    \
    && cd /usr/src \
    && pip3 install --no-cache-dir wheel six numpy \
    && pip3 install --no-cache-dir --no-deps keras_applications==1.0.6 keras_preprocessing==1.0.5 \
    && git clone -b v$TENSORFLOW_VERSION --depth 1 https://github.com/tensorflow/tensorflow \
    && cd /usr/src/tensorflow \
    && sed -i -e '/define TF_GENERATE_BACKTRACE/d' tensorflow/core/platform/default/stacktrace.h \
    && sed -i -e '/define TF_GENERATE_STACKTRACE/d' tensorflow/core/platform/stacktrace_handler.cc \
    && PYTHON_BIN_PATH=/usr/local/bin/python3 PYTHON_LIB_PATH=/usr/local/lib/python3.7/site-packages \
        CC_OPT_FLAGS="-mtune=generic" TF_NEED_JEMALLOC=1 TF_CUDA_CLANG=0 TF_NEED_GCP=0 TF_NEED_HDFS=0 \
        TF_NEED_S3=0 TF_ENABLE_XLA=0 TF_NEED_GDR=0 TF_NEED_VERBS=0 TF_CUDA_CLANG=0 TF_NEED_ROCM=0 \
        TF_NEED_OPENCL_SYCL=0 TF_NEED_OPENCL=0 TF_NEED_CUDA=0 TF_NEED_MPI=0 TF_NEED_IGNITE=0 \
        TF_DOWNLOAD_CLANG=0 TF_SET_ANDROID_WORKSPACE=0 \
        python3 configure.py \
    && bazel build --config=opt --cxxopt="-D_GLIBCXX_USE_CXX11_ABI=0" --noincompatible_strict_action_env \
        //tensorflow/tools/pip_package:build_pip_package \
    && ./bazel-bin/tensorflow/tools/pip_package/build_pip_package /usr/src/wheels \
    \
    && cd /usr/src/wheels \
    && pip3 wheel --wheel-dir /usr/src/wheels/ \
        --find-links "https://wheels.home-assistant.io/alpine-$(cut -d '.' -f 1-2 < /etc/alpine-release)/${BUILD_ARCH}/" \
        tensorflow-1.13.2-*.whl \
    && rm -rf /usr/src/tensorflow \
    && rm -f /usr/bin/bazel \
    && rm -rf /usr/src/bazel-$BAZEL_VERSION \
    && rm -rf /usr/src/hdf5-$HDF5_VERSION \
    && apk del .build-dependencies
