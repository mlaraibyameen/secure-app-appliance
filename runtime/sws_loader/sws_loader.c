#include "php.h"

#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SWS_MAGIC_LEN 8
#define SWS_IV_LEN 16
#define SWS_TAG_LEN 32
#define SWS_MASTER_LEN 64
#define SWS_KEY_LEN 32

static const unsigned char sws_magic[SWS_MAGIC_LEN] = {
    'S', 'W', 'S', '1', 'P', 'H', 'P', '\0'
};

static unsigned char sws_enc_key[SWS_KEY_LEN];
static unsigned char sws_mac_key[SWS_KEY_LEN];
static int sws_key_ready = 0;

static const php_stream_wrapper_ops *sws_original_file_wops = NULL;

typedef struct {
    zend_string *data;
    size_t position;
} sws_plain_stream_data;

static ssize_t sws_plain_write(
    php_stream *stream,
    const char *buf,
    size_t count
)
{
    return -1;
}

static ssize_t sws_plain_read(
    php_stream *stream,
    char *buf,
    size_t count
)
{
    sws_plain_stream_data *state =
        (sws_plain_stream_data *) stream->abstract;

    size_t length;
    size_t remaining;
    size_t amount;

    if (!state || !state->data) {
        return -1;
    }

    length = ZSTR_LEN(state->data);

    if (state->position >= length) {
        stream->eof = 1;
        return 0;
    }

    remaining = length - state->position;
    amount = count < remaining ? count : remaining;

    memcpy(
        buf,
        ZSTR_VAL(state->data) + state->position,
        amount
    );

    state->position += amount;

    if (state->position >= length) {
        stream->eof = 1;
    }

    return (ssize_t) amount;
}

static int sws_plain_close(
    php_stream *stream,
    int close_handle
)
{
    sws_plain_stream_data *state =
        (sws_plain_stream_data *) stream->abstract;

    if (state) {
        if (state->data) {
            OPENSSL_cleanse(
                ZSTR_VAL(state->data),
                ZSTR_LEN(state->data)
            );

            zend_string_release(state->data);
            state->data = NULL;
        }

        OPENSSL_cleanse(
            state,
            sizeof(*state)
        );

        efree(state);
        stream->abstract = NULL;
    }

    return 0;
}

static int sws_plain_flush(
    php_stream *stream
)
{
    return 0;
}

static int sws_plain_seek(
    php_stream *stream,
    zend_off_t offset,
    int whence,
    zend_off_t *newoffset
)
{
    sws_plain_stream_data *state =
        (sws_plain_stream_data *) stream->abstract;

    zend_off_t base;
    zend_off_t target;
    zend_off_t length;

    if (!state || !state->data) {
        return -1;
    }

    length = (zend_off_t) ZSTR_LEN(state->data);

    switch (whence) {
        case SEEK_SET:
            base = 0;
            break;

        case SEEK_CUR:
            base = (zend_off_t) state->position;
            break;

        case SEEK_END:
            base = length;
            break;

        default:
            return -1;
    }

    target = base + offset;

    if (target < 0 || target > length) {
        return -1;
    }

    state->position = (size_t) target;
    stream->eof = 0;

    if (newoffset) {
        *newoffset = target;
    }

    return 0;
}

static int sws_plain_cast(
    php_stream *stream,
    int castas,
    void **ret
)
{
    return FAILURE;
}

static int sws_plain_stat(
    php_stream *stream,
    php_stream_statbuf *ssb
)
{
    return -1;
}

static int sws_plain_set_option(
    php_stream *stream,
    int option,
    int value,
    void *ptrparam
)
{
    return -1;
}

static const php_stream_ops sws_plain_stream_ops = {
    sws_plain_write,
    sws_plain_read,
    sws_plain_close,
    sws_plain_flush,
    "sws-plaintext-memory",
    sws_plain_seek,
    sws_plain_cast,
    sws_plain_stat,
    sws_plain_set_option
};

static int sws_read_master(
    unsigned char master[SWS_MASTER_LEN]
)
{
    const char *fd_text = getenv("SWS_KEY_FD");
    int fd = 3;
    size_t offset = 0;

    if (fd_text && *fd_text) {
        char *end = NULL;
        long parsed = strtol(
            fd_text,
            &end,
            10
        );

        if (
            !end ||
            *end != '\0' ||
            parsed < 0 ||
            parsed > 1024
        ) {
            return FAILURE;
        }

        fd = (int) parsed;
    }

    if (
        lseek(
            fd,
            0,
            SEEK_SET
        ) < 0 &&
        errno != ESPIPE
    ) {
        return FAILURE;
    }

    while (offset < SWS_MASTER_LEN) {
        ssize_t n = read(
            fd,
            master + offset,
            SWS_MASTER_LEN - offset
        );

        if (n <= 0) {
            return FAILURE;
        }

        offset += (size_t) n;
    }

    return SUCCESS;
}

static int sws_derive_keys(void)
{
    unsigned char master[SWS_MASTER_LEN];
    unsigned int out_len = 0;

    if (
        sws_read_master(master) != SUCCESS
    ) {
        OPENSSL_cleanse(
            master,
            sizeof(master)
        );

        return FAILURE;
    }

    if (!HMAC(
        EVP_sha256(),
        master,
        SWS_MASTER_LEN,
        (const unsigned char *) "sws-v1-encryption",
        strlen("sws-v1-encryption"),
        sws_enc_key,
        &out_len
    ) || out_len != SWS_KEY_LEN) {
        OPENSSL_cleanse(
            master,
            sizeof(master)
        );

        return FAILURE;
    }

    if (!HMAC(
        EVP_sha256(),
        master,
        SWS_MASTER_LEN,
        (const unsigned char *) "sws-v1-authentication",
        strlen("sws-v1-authentication"),
        sws_mac_key,
        &out_len
    ) || out_len != SWS_KEY_LEN) {
        OPENSSL_cleanse(
            master,
            sizeof(master)
        );

        OPENSSL_cleanse(
            sws_enc_key,
            sizeof(sws_enc_key)
        );

        return FAILURE;
    }

    OPENSSL_cleanse(
        master,
        sizeof(master)
    );

    sws_key_ready = 1;

    return SUCCESS;
}

static const char *sws_relative_path(
    const char *filename
)
{
    const char *path = filename;
    const char *root = getenv("SWS_APP_ROOT");
    size_t root_len;

    if (!root || !*root) {
        root = "/opt/app";
    }

    if (
        strncmp(
            path,
            "file://",
            7
        ) == 0
    ) {
        path += 7;
    }

    root_len = strlen(root);

    if (
        strncmp(
            path,
            root,
            root_len
        ) == 0 &&
        path[root_len] == '/'
    ) {
        return path + root_len + 1;
    }

    while (
        path[0] == '.' &&
        path[1] == '/'
    ) {
        path += 2;
    }

    return path;
}

static zend_string *sws_decrypt_blob(
    const char *filename,
    zend_string *blob
)
{
    const unsigned char *data;
    const unsigned char *iv;
    const unsigned char *tag;
    const unsigned char *ciphertext;
    const char *rel;

    size_t blob_len;
    size_t cipher_len;
    size_t rel_len;
    size_t auth_len;

    unsigned char *auth = NULL;
    unsigned char expected[SWS_TAG_LEN];
    unsigned int expected_len = 0;

    EVP_CIPHER_CTX *ctx = NULL;
    zend_string *plain = NULL;

    int out1 = 0;
    int out2 = 0;

    if (!sws_key_ready) {
        return NULL;
    }

    blob_len = ZSTR_LEN(blob);

    if (
        blob_len <
        SWS_MAGIC_LEN +
        SWS_IV_LEN +
        SWS_TAG_LEN
    ) {
        return NULL;
    }

    data =
        (const unsigned char *)
        ZSTR_VAL(blob);

    if (
        memcmp(
            data,
            sws_magic,
            SWS_MAGIC_LEN
        ) != 0
    ) {
        return NULL;
    }

    iv =
        data +
        SWS_MAGIC_LEN;

    tag =
        iv +
        SWS_IV_LEN;

    ciphertext =
        tag +
        SWS_TAG_LEN;

    cipher_len =
        blob_len -
        SWS_MAGIC_LEN -
        SWS_IV_LEN -
        SWS_TAG_LEN;

    rel = sws_relative_path(filename);
    rel_len = strlen(rel);

    if (
        rel_len >
        SIZE_MAX -
        SWS_MAGIC_LEN -
        1 -
        SWS_IV_LEN -
        cipher_len
    ) {
        return NULL;
    }

    auth_len =
        SWS_MAGIC_LEN +
        rel_len +
        1 +
        SWS_IV_LEN +
        cipher_len;

    auth = emalloc(auth_len);

    memcpy(
        auth,
        sws_magic,
        SWS_MAGIC_LEN
    );

    memcpy(
        auth + SWS_MAGIC_LEN,
        rel,
        rel_len
    );

    auth[
        SWS_MAGIC_LEN +
        rel_len
    ] = '\0';

    memcpy(
        auth +
        SWS_MAGIC_LEN +
        rel_len +
        1,
        iv,
        SWS_IV_LEN
    );

    memcpy(
        auth +
        SWS_MAGIC_LEN +
        rel_len +
        1 +
        SWS_IV_LEN,
        ciphertext,
        cipher_len
    );

    if (!HMAC(
        EVP_sha256(),
        sws_mac_key,
        SWS_KEY_LEN,
        auth,
        auth_len,
        expected,
        &expected_len
    )) {
        OPENSSL_cleanse(
            auth,
            auth_len
        );

        efree(auth);

        return NULL;
    }

    OPENSSL_cleanse(
        auth,
        auth_len
    );

    efree(auth);

    if (
        expected_len != SWS_TAG_LEN ||
        CRYPTO_memcmp(
            expected,
            tag,
            SWS_TAG_LEN
        ) != 0
    ) {
        OPENSSL_cleanse(
            expected,
            sizeof(expected)
        );

        return NULL;
    }

    OPENSSL_cleanse(
        expected,
        sizeof(expected)
    );

    plain = zend_string_alloc(
        cipher_len,
        0
    );

    ctx = EVP_CIPHER_CTX_new();

    if (!ctx) {
        zend_string_release(plain);
        return NULL;
    }

    if (
        EVP_DecryptInit_ex(
            ctx,
            EVP_aes_256_ctr(),
            NULL,
            sws_enc_key,
            iv
        ) != 1
    ) {
        EVP_CIPHER_CTX_free(ctx);
        zend_string_release(plain);
        return NULL;
    }

    if (
        EVP_DecryptUpdate(
            ctx,
            (unsigned char *)
            ZSTR_VAL(plain),
            &out1,
            ciphertext,
            (int) cipher_len
        ) != 1
    ) {
        EVP_CIPHER_CTX_free(ctx);
        zend_string_release(plain);
        return NULL;
    }

    if (
        EVP_DecryptFinal_ex(
            ctx,
            (unsigned char *)
            ZSTR_VAL(plain) +
            out1,
            &out2
        ) != 1
    ) {
        EVP_CIPHER_CTX_free(ctx);
        zend_string_release(plain);
        return NULL;
    }

    EVP_CIPHER_CTX_free(ctx);

    ZSTR_LEN(plain) =
        (size_t) out1 +
        (size_t) out2;

    ZSTR_VAL(plain)[
        ZSTR_LEN(plain)
    ] = '\0';

    return plain;
}

static php_stream *sws_stream_opener(
    php_stream_wrapper *wrapper,
    const char *filename,
    const char *mode,
    int options,
    zend_string **opened_path,
    php_stream_context *context
    STREAMS_DC
)
{
    php_stream *stream;
    unsigned char header[SWS_MAGIC_LEN];
    ssize_t read_len;
    zend_string *blob;
    zend_string *plain;
    sws_plain_stream_data *state;
    php_stream *memory;

    if (
        !sws_original_file_wops ||
        !sws_original_file_wops->stream_opener
    ) {
        return NULL;
    }

    stream =
        sws_original_file_wops->stream_opener(
            wrapper,
            filename,
            mode,
            options,
            opened_path,
            context
            STREAMS_CC
        );

    if (!stream) {
        return NULL;
    }

    if (
        !strchr(mode, 'r') &&
        !strchr(mode, '+')
    ) {
        return stream;
    }

    read_len = php_stream_read(
        stream,
        (char *) header,
        SWS_MAGIC_LEN
    );

    php_stream_seek(
        stream,
        0,
        SEEK_SET
    );

    if (
        read_len != SWS_MAGIC_LEN ||
        memcmp(
            header,
            sws_magic,
            SWS_MAGIC_LEN
        ) != 0
    ) {
        return stream;
    }

    blob = php_stream_copy_to_mem(
        stream,
        PHP_STREAM_COPY_ALL,
        0
    );

    php_stream_close(stream);

    if (!blob) {
        php_error_docref(
            NULL,
            E_WARNING,
            "unable to read protected source: %s",
            filename
        );

        return NULL;
    }

    plain = sws_decrypt_blob(
        filename,
        blob
    );

    zend_string_release(blob);

    if (!plain) {
        php_error_docref(
            NULL,
            E_WARNING,
            "protected source authentication or decryption failed: %s",
            filename
        );

        return NULL;
    }

    state = emalloc(
        sizeof(*state)
    );

    state->data = plain;
    state->position = 0;

    memory = php_stream_alloc(
        &sws_plain_stream_ops,
        state,
        NULL,
        "rb"
    );

    if (!memory) {
        OPENSSL_cleanse(
            ZSTR_VAL(plain),
            ZSTR_LEN(plain)
        );

        zend_string_release(plain);

        OPENSSL_cleanse(
            state,
            sizeof(*state)
        );

        efree(state);

        return NULL;
    }

    return memory;
}

static int sws_url_stat(
    php_stream_wrapper *wrapper,
    const char *url,
    int flags,
    php_stream_statbuf *ssb,
    php_stream_context *context
)
{
    return sws_original_file_wops->url_stat(
        wrapper,
        url,
        flags,
        ssb,
        context
    );
}

static php_stream *sws_dir_opener(
    php_stream_wrapper *wrapper,
    const char *filename,
    const char *mode,
    int options,
    zend_string **opened_path,
    php_stream_context *context
    STREAMS_DC
)
{
    return sws_original_file_wops->dir_opener(
        wrapper,
        filename,
        mode,
        options,
        opened_path,
        context
        STREAMS_CC
    );
}

static int sws_unlink(
    php_stream_wrapper *wrapper,
    const char *url,
    int options,
    php_stream_context *context
)
{
    return sws_original_file_wops->unlink(
        wrapper,
        url,
        options,
        context
    );
}

static int sws_rename(
    php_stream_wrapper *wrapper,
    const char *url_from,
    const char *url_to,
    int options,
    php_stream_context *context
)
{
    return sws_original_file_wops->rename(
        wrapper,
        url_from,
        url_to,
        options,
        context
    );
}

static int sws_mkdir(
    php_stream_wrapper *wrapper,
    const char *url,
    int mode,
    int options,
    php_stream_context *context
)
{
    return sws_original_file_wops->stream_mkdir(
        wrapper,
        url,
        mode,
        options,
        context
    );
}

static int sws_rmdir(
    php_stream_wrapper *wrapper,
    const char *url,
    int options,
    php_stream_context *context
)
{
    return sws_original_file_wops->stream_rmdir(
        wrapper,
        url,
        options,
        context
    );
}

static int sws_metadata(
    php_stream_wrapper *wrapper,
    const char *url,
    int options,
    void *value,
    php_stream_context *context
)
{
    return sws_original_file_wops->stream_metadata(
        wrapper,
        url,
        options,
        value,
        context
    );
}

static const php_stream_wrapper_ops sws_file_wops = {
    sws_stream_opener,
    NULL,
    NULL,
    sws_url_stat,
    sws_dir_opener,
    "SWS protected file",
    sws_unlink,
    sws_rename,
    sws_mkdir,
    sws_rmdir,
    sws_metadata
};

PHP_MINIT_FUNCTION(sws_loader)
{
    php_stream_wrapper *plain_wrapper =
        (php_stream_wrapper *)
        &php_plain_files_wrapper;

    if (
        sws_derive_keys() != SUCCESS
    ) {
        fprintf(
            stderr,
            "sws_loader: unable to read unlock key\n"
        );

        return FAILURE;
    }

    sws_original_file_wops =
        plain_wrapper->wops;

    if (!sws_original_file_wops) {
        return FAILURE;
    }

    plain_wrapper->wops =
        &sws_file_wops;

    return SUCCESS;
}

PHP_MSHUTDOWN_FUNCTION(sws_loader)
{
    php_stream_wrapper *plain_wrapper =
        (php_stream_wrapper *)
        &php_plain_files_wrapper;

    if (sws_original_file_wops) {
        plain_wrapper->wops =
            sws_original_file_wops;

        sws_original_file_wops = NULL;
    }

    OPENSSL_cleanse(
        sws_enc_key,
        sizeof(sws_enc_key)
    );

    OPENSSL_cleanse(
        sws_mac_key,
        sizeof(sws_mac_key)
    );

    sws_key_ready = 0;

    return SUCCESS;
}

zend_module_entry sws_loader_module_entry = {
    STANDARD_MODULE_HEADER,
    "sws_loader",
    NULL,
    PHP_MINIT(sws_loader),
    PHP_MSHUTDOWN(sws_loader),
    NULL,
    NULL,
    NULL,
    "1.0.0",
    STANDARD_MODULE_PROPERTIES
};

ZEND_GET_MODULE(sws_loader)
