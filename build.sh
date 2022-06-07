#!/bin/env bash

#set -o noclobber
set -o errexit
set -o pipefail
set -o nounset

ZLIB=zlib-1.2.12
PCRE=pcre-8.45
OPENSSL=openssl-1.1.1o

WORK_DIR=$(cd $(dirname $0);pwd)
DEPS_DIR=$WORK_DIR/deps
MODULES_DIR=$WORK_DIR/modules
OPENSSL_IFE_DIR=/export/servers/openssl_ife

WITH_SSL=""
SSL_INC=""
SSL_LIB=""
if [ "${SSL-}x" == "staticx" ]; then
    WITH_SSL="--with-openssl=$DEPS_DIR/${OPENSSL} "
    SSL_LIB="-pthread"
else
    SSL_INC="-I $OPENSSL_IFE_DIR/include"
    SSL_LIB="-L $OPENSSL_IFE_DIR/lib"
    export LD_LIBRARY_PATH=${OPENSSL_IFE_DIR}/lib:${LD_LIBRARY_PATH:-.}
fi

if [ $HOME == '/' ]; then
   exit
fi

function my_init() {
    DESTDIR=$1
    PREFIX=$2
    DEBUG=$3
}

#----------pre-------------

function my_build_deplibs() {
    #nginx依赖库
    cd $DEPS_DIR
    tar xvzf ${PCRE}.tar.gz && tar xvzf ${ZLIB}.tar.gz && tar xvzf ${OPENSSL}.tar.gz
}


#----------before build-------------
function my_build_pre() {
    my_build_deplibs
}

function my_configure_ife() {

    local debug=""

    if [ "${DEBUG}d" == "debugd" ]; then
        debug="--with-debug"
    fi
    
    cd $WORK_DIR/nginx && ./configure    \
        --prefix=$PREFIX            \
        --with-cc=gcc                        \
        --with-cc-opt="-Wall -Werror -ggdb -fno-omit-frame-pointer -O2 $SSL_INC " \
        --with-ld-opt="$SSL_LIB"                                           \
        --with-openssl-opt="enable-tls1_3 enable-weak-ssl-ciphers"         \
        ${WITH_SSL}                                                        \
        --with-pcre=$DEPS_DIR/${PCRE}                                      \
        --with-zlib=$DEPS_DIR/${ZLIB}                                      \
        --with-pcre-jit                 \
        --with-threads                  \
        --with-http_auth_request_module \
        --with-http_ssl_module          \
        --with-http_gzip_static_module  \
        --with-http_stub_status_module  \
        --with-http_v2_module           \
        --with-http_addition_module     \
        --with-http_slice_module        \
        --with-stream                          \
        --with-stream_ssl_module               \
        --with-stream_ssl_preread_module       \
        --without-http_echo_module             \
        --without-http_xss_module              \
        --without-http_coolkit_module          \
        --without-http_form_input_module       \
        --without-http_encrypted_session_module \
        --without-http_srcache_module           \
        --without-http_array_var_module         \
        --without-http_memc_module              \
        --without-http_redis_module             \
        --without-http_redis2_module            \
        --without-http_rds_json_module          \
        --without-http_rds_csv_module           \
        $debug
}

function my_build() {
    echo "========= Building IFE ==========="
    my_build_pre
    my_configure_ife
    
    cd $WORK_DIR/openresty && make -j 24
    echo "========= Successfully built IFE ==========="
}

#------------------------- install -----------------------
function my_install_openresty() {
    cd $WORK_DIR/openresty && make DESTDIR=$DESTDIR install
}

function my_install_ife_conf() {
    #安装配置文件
    local IFE_CONF=$DESTDIR/$PREFIX/conf
    
    install -d $IFE_CONF

    install -d $IFE_CONF/localconfs/
    #install $WORK_DIR/conf/localconfs/* $IFE_CONF/localconfs/

    install -d $IFE_CONF/certs/
    #install $WORK_DIR/conf/certs/* $IFE_CONF/certs/
    
    install $WORK_DIR/conf/nginx.conf $IFE_CONF/
    install $WORK_DIR/conf/mime.types $IFE_CONF/

    install -d $IFE_CONF/modsecurity/
    install $WORK_DIR/conf/modsecurity/*.conf $IFE_CONF/modsecurity/
    install $WORK_DIR/conf/modsecurity/unicode.mapping $IFE_CONF/modsecurity/

    install -d $IFE_CONF/modsecurity/rules
    install $WORK_DIR/conf/modsecurity/rules/* $IFE_CONF/modsecurity/rules/

    return
}

function my_install_script() {
    install -d $DESTDIR/$PREFIX/bin/
    install $WORK_DIR/bin/control $DESTDIR/$PREFIX/bin/

    install -d $DESTDIR/$PREFIX/sbin
    ln -s ../nginx/sbin/nginx $DESTDIR/$PREFIX/sbin/nginx
}

function my_install_deplibs() {
	install -d $DESTDIR/$PREFIX/libs/
    #install $WORK_DIR/libs/* $DESTDIR/$PREFIX/libs
    
    # 用打包环境的lib 替换
    #/bin/cp -f /lib64/libjson-c.so.* $DESTDIR/$PREFIX/libs/.
    install $DEPS_DIR/modsecurity/src/.libs/libmodsecurity.so* $DESTDIR/$PREFIX/libs
    
    if [ "${DEBUG}d" == "debugd" ]; then
        /bin/cp -f $DESTDIR/$PREFIX/luajit/lib/libluajit-5.1.so.* $DESTDIR/$PREFIX/libs/.
    fi
}

function my_clean_other() {
    if [ -d $DESTDIR/$PREFIX/luajit ]; then
        rm -rf $DESTDIR/$PREFIX/luajit
    fi
    if [ -d $DESTDIR/$PREFIX/pod ]; then
        rm -rf $DESTDIR/$PREFIX/pod
    fi
    if [ -d $DESTDIR/$PREFIX/site ]; then
        rm -rf $DESTDIR/$PREFIX/site
    fi
    if [ -f $DESTDIR/$PREFIX/bin/openresty ]; then
        rm -f $DESTDIR/$PREFIX/bin/openresty
    fi
}

function my_install() {
    echo "========= Installing IFE ==========="
    my_install_openresty
    
    my_install_ife_conf
    my_install_script
    my_install_deplibs
    if [ "${DEBUG}d" != "debugd" ]; then
        my_clean_other
    fi
    echo "========= Successfully installed IFE ==========="
}

function my_rpm() {
    echo "========= Building RPM IFE ==========="
    echo "========= Successfully built RPM IFE ==========="
}

function my_clean() {
    cd $DEPS_DIR/modsecurity && make clean
    cd $WORK_DIR/openresty && make clean
    rm -rf $WORK_DIR/output
}

function main() {
    if [ $# == 3 ]; then
        my_init $2 $3 ""
    elif [ $# == 2 ]; then
        my_init "" $WORK_DIR/output $2
    else
        my_init "" $WORK_DIR/output ""
    fi

    if [ $# == 0 ]; then
        my_build
         
        my_install
        exit
    fi

    case $1 in
        build)
        my_build
        ;;
        install)
        my_install
        ;;
        clean)
        my_clean
        ;;
        package)
        my_build
        my_install
        ;;
        rpm)
        my_rpm
        ;;
        *)
        echo "usage: $0 {build|install|clean|rpm}"
    esac
}

main $@



