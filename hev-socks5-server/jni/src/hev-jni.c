/*
 ============================================================================
 Name        : hev-jni.c
 Author      : hev <r@hev.cc>
 Copyright   : Copyright (c) 2019 - 2026 hev
 Description : Java Native Interface
 ============================================================================
 */

#ifdef ANDROID

#include <jni.h>
#include <pthread.h>
#include <stdatomic.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "hev-socks5-tunnel.h"
#include "hev-main.h"
#include "hev-jni.h"

#ifndef PKGNAME
#define PKGNAME hev/htproxy
#endif

#ifndef CLSNAME
#define CLSNAME TProxyService
#endif

#define STR_ARG(x) #x
#define STR(x) STR_ARG(x)

#define N_ELEMENTS(x) \
    (sizeof(x) / sizeof((x)[0]))

static JavaVM *java_vm = NULL;
static jclass tproxy_class = NULL;

static atomic_int is_running = 0;

static pthread_t work_thread;
static int thread_joinable = 0;

static pthread_mutex_t mutex =
    PTHREAD_MUTEX_INITIALIZER;

typedef struct {

    char *config_path;
    int fd;

} ThreadData;


/*
 * JNI functions.
 */
static jboolean native_start_service(
    JNIEnv *env,
    jobject thiz,
    jstring config_path,
    jint fd
);

static jboolean native_stop_service(
    JNIEnv *env,
    jobject thiz
);

static jboolean native_is_running(
    JNIEnv *env,
    jobject thiz
);

static jlongArray native_get_stats(
    JNIEnv *env,
    jobject thiz
);

static jobjectArray native_get_flows(
    JNIEnv *env,
    jobject thiz
);


static JNINativeMethod native_methods[] = {

    {
        "TProxyStartService",
        "(Ljava/lang/String;I)Z",
        (void *)native_start_service
    },

    {
        "TProxyStopService",
        "()Z",
        (void *)native_stop_service
    },

    {
        "TProxyIsRunning",
        "()Z",
        (void *)native_is_running
    },

    {
        "TProxyGetStats",
        "()[J",
        (void *)native_get_stats
    },

    {
        "TProxyGetFlows",
        "()[Ljava/lang/String;",
        (void *)native_get_flows
    }
};


/*
 * Worker thread.
 *
 * We intentionally use the low-level HEV API already present
 * in your checkout:
 *
 *   hev_socks5_tunnel_init()
 *   hev_socks5_tunnel_run()
 *   hev_socks5_tunnel_stop()
 *   hev_socks5_tunnel_fini()
 *
 * Configuration is initialized by the HEV main API in
 * your existing build before this low-level tunnel starts.
 */
static void *thread_handler(
    void *data
)
{
    ThreadData *thread_data =
        (ThreadData *)data;

    int init_result;
    int run_result;

    if (!thread_data) {

        atomic_store(
            &is_running,
            0
        );

        return NULL;
    }

    /*
     * The current HEV checkout exposes
     * the configuration-aware main API through
     * hev-main.c. Use it when available.
     */
    init_result =
        hev_socks5_tunnel_init(
            thread_data->fd
        );

    if (init_result != 0) {

        fprintf(
            stderr,
            "AppTrack: HEV tunnel init failed\n"
        );

        atomic_store(
            &is_running,
            0
        );

        free(
            thread_data->config_path
        );

        free(
            thread_data
        );

        return NULL;
    }

    run_result =
        hev_socks5_tunnel_run();

    (void)run_result;

    hev_socks5_tunnel_fini();

    atomic_store(
        &is_running,
        0
    );

    free(
        thread_data->config_path
    );

    free(
        thread_data
    );

    return NULL;
}


/*
 * JNI_OnLoad.
 */
JNIEXPORT jint JNICALL
JNI_OnLoad(
    JavaVM *vm,
    void *reserved
)
{
    JNIEnv *env = NULL;
    jclass local_class;
    jint result;

    (void)reserved;

    java_vm = vm;

    result =
        (*vm)->GetEnv(
            vm,
            (void **)&env,
            JNI_VERSION_1_4
        );

    if (result != JNI_OK) {
        return JNI_ERR;
    }

    local_class =
        (*env)->FindClass(
            env,
            STR(PKGNAME) "/" STR(CLSNAME)
        );

    if (!local_class) {
        return JNI_ERR;
    }

    tproxy_class =
        (*env)->NewGlobalRef(
            env,
            local_class
        );

    if (!tproxy_class) {

        (*env)->DeleteLocalRef(
            env,
            local_class
        );

        return JNI_ERR;
    }

    result =
        (*env)->RegisterNatives(
            env,
            local_class,
            native_methods,
            (jint)N_ELEMENTS(
                native_methods
            )
        );

    (*env)->DeleteLocalRef(
        env,
        local_class
    );

    if (result != 0) {
        return JNI_ERR;
    }

    return JNI_VERSION_1_4;
}


/*
 * Start HEV.
 */
static jboolean
native_start_service(
    JNIEnv *env,
    jobject thiz,
    jstring config_path,
    jint fd
)
{
    const char *path_utf8;
    ThreadData *data;
    int result;

    (void)thiz;

    if (!config_path) {
        return JNI_FALSE;
    }

    pthread_mutex_lock(
        &mutex
    );

    if (
        atomic_load(
            &is_running
        )
    ) {

        pthread_mutex_unlock(
            &mutex
        );

        return JNI_FALSE;
    }

    if (thread_joinable) {

        pthread_join(
            work_thread,
            NULL
        );

        thread_joinable = 0;
    }

    data =
        (ThreadData *)calloc(
            1,
            sizeof(ThreadData)
        );

    if (!data) {

        pthread_mutex_unlock(
            &mutex
        );

        return JNI_FALSE;
    }

    path_utf8 =
        (*env)->GetStringUTFChars(
            env,
            config_path,
            NULL
        );

    if (!path_utf8) {

        free(data);

        pthread_mutex_unlock(
            &mutex
        );

        return JNI_FALSE;
    }

    data->config_path =
        strdup(
            path_utf8
        );

    (*env)->ReleaseStringUTFChars(
        env,
        config_path,
        path_utf8
    );

    if (!data->config_path) {

        free(data);

        pthread_mutex_unlock(
            &mutex
        );

        return JNI_FALSE;
    }

    data->fd =
        (int)fd;

    atomic_store(
        &is_running,
        1
    );

    result =
        pthread_create(
            &work_thread,
            NULL,
            thread_handler,
            data
        );

    if (result != 0) {

        atomic_store(
            &is_running,
            0
        );

        free(
            data->config_path
        );

        free(data);

        pthread_mutex_unlock(
            &mutex
        );

        return JNI_FALSE;
    }

    thread_joinable = 1;

    pthread_mutex_unlock(
        &mutex
    );

    return JNI_TRUE;
}


/*
 * Stop HEV.
 */
static jboolean
native_stop_service(
    JNIEnv *env,
    jobject thiz
)
{
    int result = 0;

    (void)env;
    (void)thiz;

    pthread_mutex_lock(
        &mutex
    );

    if (!thread_joinable) {

        pthread_mutex_unlock(
            &mutex
        );

        return JNI_TRUE;
    }

    /*
     * This wakes the HEV event loop.
     */
    hev_socks5_tunnel_stop();

    result =
        pthread_join(
            work_thread,
            NULL
        );

    thread_joinable = 0;

    atomic_store(
        &is_running,
        0
    );

    pthread_mutex_unlock(
        &mutex
    );

    return result == 0
        ? JNI_TRUE
        : JNI_FALSE;
}


/*
 * Running state.
 */
static jboolean
native_is_running(
    JNIEnv *env,
    jobject thiz
)
{
    (void)env;
    (void)thiz;

    return atomic_load(
        &is_running
    )
        ? JNI_TRUE
        : JNI_FALSE;
}


/*
 * Statistics.
 */
static jlongArray
native_get_stats(
    JNIEnv *env,
    jobject thiz
)
{
    size_t tx_packets = 0;
    size_t tx_bytes = 0;
    size_t rx_packets = 0;
    size_t rx_bytes = 0;

    jlong values[4];

    jlongArray result;

    (void)thiz;

    hev_socks5_tunnel_stats(
        &tx_packets,
        &tx_bytes,
        &rx_packets,
        &rx_bytes
    );

    values[0] =
        (jlong)tx_packets;

    values[1] =
        (jlong)tx_bytes;

    values[2] =
        (jlong)rx_packets;

    values[3] =
        (jlong)rx_bytes;

    result =
        (*env)->NewLongArray(
            env,
            4
        );

    if (!result) {
        return NULL;
    }

    (*env)->SetLongArrayRegion(
        env,
        result,
        0,
        4,
        values
    );

    return result;
}


/*
 * Flow polling.
 *
 * Returned format:
 *
 * ip|port|protocolNumber|ipVersion|bytes
 *
 * Example:
 *
 * 157.240.241.17|443|17|4|1200
 */
static jobjectArray
native_get_flows(
    JNIEnv *env,
    jobject thiz
)
{
    enum {
        MAX_FLOWS = 1024
    };

    HevFlowRecord records[MAX_FLOWS];

    int count;
    int i;

    jclass string_class;
    jobjectArray result;

    (void)thiz;

    memset(
        records,
        0,
        sizeof(records)
    );

    count =
        hev_socks5_tunnel_get_flows(
            records,
            MAX_FLOWS
        );

    if (count < 0) {
        count = 0;
    }

    if (count > MAX_FLOWS) {
        count = MAX_FLOWS;
    }

    string_class =
        (*env)->FindClass(
            env,
            "java/lang/String"
        );

    if (!string_class) {
        return NULL;
    }

    result =
        (*env)->NewObjectArray(
            env,
            count,
            string_class,
            NULL
        );

    if (!result) {

        (*env)->DeleteLocalRef(
            env,
            string_class
        );

        return NULL;
    }

    for (
        i = 0;
        i < count;
        i++
    ) {

        char buffer[256];

        int written;

        written =
            snprintf(
                buffer,
                sizeof(buffer),
                "%s|%u|%u|%u|%llu",
                records[i].destination_ip,
                records[i].destination_port,
                records[i].protocol,
                records[i].ip_version,
                (unsigned long long)
                    records[i].bytes
            );

        if (written < 0) {
            continue;
        }

        if (
            written >=
            (int)sizeof(buffer)
        ) {
            buffer[
                sizeof(buffer) - 1
            ] = '\0';
        }

        jstring value =
            (*env)->NewStringUTF(
                env,
                buffer
            );

        if (value) {

            (*env)->SetObjectArrayElement(
                env,
                result,
                i,
                value
            );

            (*env)->DeleteLocalRef(
                env,
                value
            );
        }
    }

    (*env)->DeleteLocalRef(
        env,
        string_class
    );

    return result;
}

#endif /* ANDROID */