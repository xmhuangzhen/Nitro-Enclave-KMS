
FROM amazonlinux as builder

RUN yum upgrade -y
RUN amazon-linux-extras enable epel
RUN yum clean -y metadata && yum install -y epel-release
RUN yum install -y cmake3 gcc git tar make
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain 1.55

RUN yum install -y gcc-c++
RUN yum install -y go
RUN yum install -y ninja-build

# We keep the build artifacts in the -build directory
WORKDIR /tmp/crt-builder

RUN git clone -b v1.0.2 https://github.com/awslabs/aws-lc.git aws-lc #
RUN cmake3 -DCMAKE_PREFIX_PATH=/usr -DCMAKE_INSTALL_PREFIX=/usr -GNinja -S aws-lc -B aws-lc/build .
RUN cmake3 --build aws-lc/build --target install

RUN git clone -b v1.3.9 https://github.com/aws/s2n-tls.git
RUN cmake3 -DCMAKE_PREFIX_PATH=/usr -DCMAKE_INSTALL_PREFIX=/usr -S s2n-tls -B s2n-tls/build
RUN cmake3 --build s2n-tls/build --target install

RUN git clone -b v0.6.11 https://github.com/awslabs/aws-c-common.git
RUN cmake3 -DCMAKE_PREFIX_PATH=/usr -DCMAKE_INSTALL_PREFIX=/usr -GNinja -S aws-c-common -B aws-c-common/build
RUN cmake3 --build aws-c-common/build --target install

RUN git clone -b v0.5.14 https://github.com/awslabs/aws-c-cal.git
RUN cmake3 -DCMAKE_PREFIX_PATH=/usr -DCMAKE_INSTALL_PREFIX=/usr -GNinja -S aws-c-cal -B aws-c-cal/build
RUN cmake3 --build aws-c-cal/build --target install

RUN git clone -b v0.10.9 https://github.com/awslabs/aws-c-io.git
RUN cmake3 -DUSE_VSOCK=1 -DCMAKE_PREFIX_PATH=/usr -DCMAKE_INSTALL_PREFIX=/usr -GNinja -S aws-c-io -B aws-c-io/build
RUN cmake3 --build aws-c-io/build --target install

RUN git clone -b v0.2.14 http://github.com/awslabs/aws-c-compression.git
RUN cmake3 -DCMAKE_PREFIX_PATH=/usr -DCMAKE_INSTALL_PREFIX=/usr -GNinja -S aws-c-compression -B aws-c-compression/build
RUN cmake3 --build aws-c-compression/build --target install

RUN git clone -b v0.6.7 https://github.com/awslabs/aws-c-http.git
RUN cmake3 -DCMAKE_PREFIX_PATH=/usr -DCMAKE_INSTALL_PREFIX=/usr -GNinja -S aws-c-http -B aws-c-http/build
RUN cmake3 --build aws-c-http/build --target install

RUN git clone -b v0.6.4 https://github.com/awslabs/aws-c-auth.git
RUN cmake3 -DCMAKE_PREFIX_PATH=/usr -DCMAKE_INSTALL_PREFIX=/usr -GNinja -S aws-c-auth -B aws-c-auth/build
RUN cmake3 --build aws-c-auth/build --target install

RUN git clone -b json-c-0.15-20200726 https://github.com/json-c/json-c.git
RUN cmake3 -DCMAKE_PREFIX_PATH=/usr -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=OFF -GNinja -S json-c -B json-c/build
RUN cmake3 --build json-c/build --target install

RUN git clone -b v0.1.0 https://github.com/aws/aws-nitro-enclaves-nsm-api.git
RUN source $HOME/.cargo/env && cd aws-nitro-enclaves-nsm-api && cargo build --release
RUN mv aws-nitro-enclaves-nsm-api/target/release/libnsm.so /usr/lib64
RUN mv aws-nitro-enclaves-nsm-api/target/release/nsm.h /usr/include


RUN yum install -y doxygen
COPY . aws-nitro-enclaves-sdk-c
RUN cmake3 -DCMAKE_PREFIX_PATH=/usr -DCMAKE_INSTALL_PREFIX=/usr -GNinja \
	-S aws-nitro-enclaves-sdk-c -B aws-nitro-enclaves-sdk-c/build
RUN cmake3 --build aws-nitro-enclaves-sdk-c/build --target install
RUN cmake3 --build aws-nitro-enclaves-sdk-c/build --target docs

# Test
FROM builder as test
RUN cmake3 --build aws-nitro-enclaves-sdk-c/build --target test

# kmstool-enclave
FROM amazonlinux as kmstool-enclave

# TODO: building packages statically instead of cleaning up unwanted packages from amazonlinux
RUN rpm -e python python-libs python-urlgrabber python2-rpm pygpgme pyliblzma python-iniparse pyxattr python-pycurl amazon-linux-extras yum yum-metadata-parser yum-plugin-ovl yum-plugin-priorities
COPY --from=builder /usr/lib64/libnsm.so /usr/lib64/libnsm.so
COPY --from=builder /usr/bin/kmstool_enclave /kmstool_enclave
CMD ["/kmstool_enclave"]

# kmstool-instance
FROM amazonlinux as kmstool-instance

# TODO: building packages statically instead of cleaning up unwanted packages from amazonlinux
RUN rpm -e python python-libs python-urlgrabber python2-rpm pygpgme pyliblzma python-iniparse pyxattr python-pycurl amazon-linux-extras yum yum-metadata-parser yum-plugin-ovl yum-plugin-priorities
COPY --from=builder /usr/lib64/libnsm.so /usr/lib64/libnsm.so
COPY --from=builder /usr/bin/kmstool_instance /kmstool_instance
CMD ["/kmstool_instance"]

# kmstool-enclave-cli
FROM amazonlinux as kmstool-enclave-cli

# TODO: building packages statically instead of cleaning up unwanted packages from amazonlinux
RUN rpm -e python python-libs python-urlgrabber python2-rpm pygpgme pyliblzma python-iniparse pyxattr python-pycurl amazon-linux-extras yum yum-metadata-parser yum-plugin-ovl yum-plugin-priorities
COPY --from=builder /usr/lib64/libnsm.so /usr/lib64/libnsm.so
COPY --from=builder /usr/bin/kmstool_enclave_cli /kmstool_enclave_cli

WORKDIR /app

COPY requirements.txt ./
RUN pip3 install -r /app/requirements.txt

COPY server.py ./
COPY traffic_forwarder.py ./
COPY run.sh ./

RUN chmod +x /app/run.sh

CMD ["/app/run.sh"]