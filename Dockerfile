ARG BUILD_FROM
FROM $BUILD_FROM

ARG BUILD_ARCH
ARG TENSORFLOW_VERSION=2.3.0
ARG BAZEL_VERSION=3.5.0
ARG SENTENCEPIECE_VERSION=0.1.92
ARG TENSORFLOW_ADDONS_VERSION=0.11.2

WORKDIR /usr/src
RUN apk add --no-cache \
        autoconf \
        automake \
        build-base \
        cmake \
        curl \
        cython \
        freetype \
        freetype-dev \
        gfortran \
        git \
        hdf5-dev \
        lapack-dev \
        libexecinfo-dev \
        libexecinfo-static \
        libjpeg-turbo \
        libjpeg-turbo-dev \
        libpng \
        libpng-dev \
        libtool \
        linux-headers \
        musl \
        openblas-dev \
        openjdk11 \
        patchelf \
        pkgconfig \
        rsync \
        sed \
        zip \
    \
    && rm -rf /usr/lib/jvm/java-11-openjdk/jre

ENV JAVA_HOME="/usr/lib/jvm/java-11-openjdk"

RUN pip3 install \
        --no-cache-dir \
        --find-links "https://wheels.home-assistant.io/alpine-$(cut -d '.' -f 1-2 < /etc/alpine-release)/${BUILD_ARCH}/" \
        wheel \
        six \
        numpy \
        auditwheel

RUN cd /usr/src \
    && git clone -b v${SENTENCEPIECE_VERSION} --depth 1 https://github.com/google/sentencepiece \
    && mkdir -p sentencepiece/build \
    && cd /usr/src/sentencepiece/build \
    && cmake .. \
    && make -j $(nproc) \
    && make install \
    && cd ../python \
    && pip3 wheel \
        --find-links "https://wheels.home-assistant.io/alpine-$(cut -d '.' -f 1-2 < /etc/alpine-release)/${BUILD_ARCH}/" \
        . \
    && export LD_LIBRARY_PATH=/usr/local/lib \
    && auditwheel repair sentencepiece-${SENTENCEPIECE_VERSION}-cp38-cp38-linux_x86_64.whl \
        --no-update-tags \
        -w /usr/src/wheels

RUN cd /usr/src \
    && curl -SLO \
        https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-$BAZEL_VERSION-dist.zip \
    && mkdir bazel-$BAZEL_VERSION \
    && unzip -qd bazel-$BAZEL_VERSION bazel-$BAZEL_VERSION-dist.zip \
    && cd /usr/src/bazel-$BAZEL_VERSION \
    && EXTRA_BAZEL_ARGS=--host_javabase=@local_jdk//:jdk ./compile.sh \
    && cp -p output/bazel /usr/bin/
    
COPY *.patch ./
RUN cd /usr/src \
    && pip3 install --no-cache-dir \
        --no-deps keras_applications==1.0.6 keras_preprocessing==1.0.5 \
    && git clone -b v${TENSORFLOW_VERSION} --depth 1 https://github.com/tensorflow/tensorflow \
    && for i in /usr/src/*.patch; do \
        patch -d /usr/src/tensorflow -p 1 < "${i}"; done

RUN cd /usr/src/tensorflow \
    && sed -i -e '/HAVE_MALLINFO/d' third_party/llvm/llvm.bzl \
    && PYTHON_BIN_PATH=/usr/local/bin/python3 PYTHON_LIB_PATH=/usr/local/lib/python3.8/site-packages \
        CC_OPT_FLAGS="-mtune=generic" TF_NEED_JEMALLOC=1 TF_CUDA_CLANG=0 TF_NEED_GCP=0 TF_NEED_HDFS=0 \
        TF_NEED_S3=0 TF_ENABLE_XLA=0 TF_NEED_GDR=0 TF_NEED_VERBS=0 TF_CUDA_CLANG=0 TF_NEED_ROCM=0 \
        TF_NEED_OPENCL_SYCL=0 TF_NEED_OPENCL=0 TF_NEED_CUDA=0 TF_NEED_MPI=0 TF_NEED_IGNITE=0 \
        TF_DOWNLOAD_CLANG=0 TF_SET_ANDROID_WORKSPACE=0 \
        python3 configure.py \
    && bazel build --config=opt \
        --cxxopt="-D_GLIBCXX_USE_CXX11_ABI=0" \
        --linkopt=-lexecinfo --host_linkopt=-lexecinfo \
        --noincompatible_strict_action_env \
        //tensorflow/tools/pip_package:build_pip_package

RUN cd /usr/src/tensorflow \
    && ./bazel-bin/tensorflow/tools/pip_package/build_pip_package /usr/src/wheels 

RUN cd /usr/src/wheels \
    && pip3 wheel \
        --wheel-dir /usr/src/wheels/ \
        --find-links "https://wheels.home-assistant.io/alpine-$(cut -d '.' -f 1-2 < /etc/alpine-release)/${BUILD_ARCH}/" \
        tensorflow-${TENSORFLOW_VERSION}-*.whl

RUN cd /usr/src/wheels \
    && pip3 install \
        --find-links "https://wheels.home-assistant.io/alpine-$(cut -d '.' -f 1-2 < /etc/alpine-release)/${BUILD_ARCH}/" \
        tensorflow-${TENSORFLOW_VERSION}-*.whl

RUN cd /usr/src \
    && git clone -b v${TENSORFLOW_ADDONS_VERSION} --depth 1 https://github.com/tensorflow/addons

RUN cd /usr/src/addons \
    && python3 ./configure.py \
    && bazel build --enable_runfiles build_pip_pkg \
    && bazel-bin/build_pip_pkg  /usr/src/wheels

RUN cd /usr/src/wheels \
    && pip3 wheel \
        --wheel-dir /usr/src/wheels/ \
        --find-links "https://wheels.home-assistant.io/alpine-$(cut -d '.' -f 1-2 < /etc/alpine-release)/${BUILD_ARCH}/" \
        *.whl \
        tf-models-official
