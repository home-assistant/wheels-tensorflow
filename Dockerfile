ARG BUILD_FROM
FROM $BUILD_FROM

ARG BUILD_ARCH
ARG TENSORFLOW_VERSION=2.2.0
ARG BAZEL_VERSION=2.0.0

WORKDIR /usr/src
RUN apk add --no-cache \
        freetype \
        libpng \
        libjpeg-turbo \
        musl \
    && apk add --no-cache --virtual=.build-dependencies \
        git \
        cmake \
        build-base \
        curl \
        linux-headers \
        openjdk11 \
        zip \
        autoconf \
        automake \
        libtool \
        sed \
        hdf5-dev \
        libexecinfo-dev \
        freetype-dev \
        libjpeg-turbo-dev \
        libpng-dev \
    \
    && rm -rf /usr/lib/jvm/java-11-openjdk/jre \
    && export JAVA_HOME="/usr/lib/jvm/java-11-openjdk" \
    \
    && cd /usr/src \
    && curl -SLO \
        https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-$BAZEL_VERSION-dist.zip \
    && mkdir bazel-$BAZEL_VERSION \
    && unzip -qd bazel-$BAZEL_VERSION bazel-$BAZEL_VERSION-dist.zip \
    && cd /usr/src/bazel-$BAZEL_VERSION \
    && EXTRA_BAZEL_ARGS=--host_javabase=@local_jdk//:jdk ./compile.sh \
    && cp -p output/bazel /usr/bin/ \
    \
    && cd /usr/src \
    && pip3 install --no-cache-dir \
        --find-links "https://wheels.home-assistant.io/alpine-$(cut -d '.' -f 1-2 < /etc/alpine-release)/${BUILD_ARCH}/" \
        wheel six numpy \
    && pip3 install --no-cache-dir \
        --no-deps keras_applications==1.0.6 keras_preprocessing==1.0.5 \
    && git clone -b v${TENSORFLOW_VERSION} --depth 1 https://github.com/tensorflow/tensorflow \
    && cd /usr/src/tensorflow \
    && sed -i -e '/define TF_HAS_STACKTRACE/d' tensorflow/core/platform/default/stacktrace.h \
    && sed -i -e '/define TF_GENERATE_STACKTRACE/d' tensorflow/core/platform/default/stacktrace_handler.cc \
    && sed -i -d '/HAVE_MALLINFO/d' third_party/llvm/llvm.bzl \
    && PYTHON_BIN_PATH=/usr/local/bin/python3 PYTHON_LIB_PATH=/usr/local/lib/python3.8/site-packages \
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
    && pip3 wheel \
        --wheel-dir /usr/src/wheels/ \
        --find-links "https://wheels.home-assistant.io/alpine-$(cut -d '.' -f 1-2 < /etc/alpine-release)/${BUILD_ARCH}/" \
        tensorflow-${TENSORFLOW_VERSION}-*.whl \
    && rm -rf /usr/src/tensorflow \
    && rm -f /usr/bin/bazel \
    && rm -rf /usr/src/bazel-$BAZEL_VERSION \
    && rm -rf /usr/src/hdf5-$HDF5_VERSION \
    && apk del .build-dependencies
