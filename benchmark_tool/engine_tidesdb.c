#include "benchmark.h"
#include <tidesdb/tidesdb.h>
#include <stdlib.h>
#include <string.h>

typedef struct
{
    tidesdb_t *db;
    tidesdb_txn_t *txn;
    tidesdb_column_family_t *cf;  /* Cache CF pointer */
} tidesdb_handle_t;

/* Forward declaration */
static const storage_engine_ops_t tidesdb_ops;

static int tidesdb_open_impl(storage_engine_t **engine, const char *path)
{
    *engine = malloc(sizeof(storage_engine_t));
    if (!*engine) return -1;

    tidesdb_handle_t *handle = malloc(sizeof(tidesdb_handle_t));
    if (!handle)
    {
        free(*engine);
        return -1;
    }

    tidesdb_config_t config;
    memset(&config, 0, sizeof(tidesdb_config_t));
    strncpy(config.db_path, path, sizeof(config.db_path) - 1);
    config.db_path[sizeof(config.db_path) - 1] = '\0';
    config.num_flush_threads = 4;
    config.num_compaction_threads = 4;
    config.enable_debug_logging = 0;

    if (tidesdb_open(&config, &handle->db) != 0)
    {
        free(handle);
        free(*engine);
        return -1;
    }

    /* Create default column family */
    tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
    cf_config.enable_compression = 1;
    cf_config.compression_algorithm = COMPRESS_LZ4;
    cf_config.enable_bloom_filter = 1;
    cf_config.enable_block_indexes = 1;
    cf_config.block_manager_cache_size = 64 * 1024 * 1024;  /* 256MB cache */
    cf_config.sync_mode = TDB_SYNC_NONE;
    cf_config.memtable_flush_size = 64 * 1024 * 1024;

    if (tidesdb_create_column_family(handle->db, "default", &cf_config) != 0)
    {
        /* Column family might already exist, which is fine */
    }

    /* Cache the column family pointer */
    handle->cf = tidesdb_get_column_family(handle->db, "default");
    if (!handle->cf)
    {
        tidesdb_close(handle->db);
        free(handle);
        free(*engine);
        return -1;
    }

    handle->txn = NULL;
    (*engine)->handle = handle;
    (*engine)->ops = &tidesdb_ops;

    return 0;
}

static int tidesdb_close_impl(storage_engine_t *engine)
{
    tidesdb_handle_t *handle = (tidesdb_handle_t *)engine->handle;
    if (handle->txn) tidesdb_txn_free(handle->txn);
    tidesdb_close(handle->db);
    free(handle);
    free(engine);
    return 0;
}

static int tidesdb_put_impl(storage_engine_t *engine, const uint8_t *key, size_t key_size,
                            const uint8_t *value, size_t value_size)
{
    tidesdb_handle_t *handle = (tidesdb_handle_t *)engine->handle;
    tidesdb_txn_t *txn = NULL;

    tidesdb_txn_begin(handle->db, handle->cf, &txn);
    int result = tidesdb_txn_put(txn, key, key_size, value, value_size, -1);
    tidesdb_txn_commit(txn);
    tidesdb_txn_free(txn);

    return result;
}

static int tidesdb_get_impl(storage_engine_t *engine, const uint8_t *key, size_t key_size,
                            uint8_t **value, size_t *value_size)
{
    tidesdb_handle_t *handle = (tidesdb_handle_t *)engine->handle;
    tidesdb_txn_t *txn = NULL;

    tidesdb_txn_begin_read(handle->db, handle->cf, &txn);
    int result = tidesdb_txn_get(txn, key, key_size, value, value_size);
    tidesdb_txn_free(txn);

    return result;
}

static int tidesdb_del_impl(storage_engine_t *engine, const uint8_t *key, size_t key_size)
{
    tidesdb_handle_t *handle = (tidesdb_handle_t *)engine->handle;
    tidesdb_txn_t *txn = NULL;

    tidesdb_txn_begin(handle->db, handle->cf, &txn);
    int result = tidesdb_txn_delete(txn, key, key_size);
    tidesdb_txn_commit(txn);
    tidesdb_txn_free(txn);

    return result;
}

static int tidesdb_iter_new_impl(storage_engine_t *engine, void **iter)
{
    tidesdb_handle_t *handle = (tidesdb_handle_t *)engine->handle;
    tidesdb_txn_t *txn = NULL;

    tidesdb_txn_begin_read(handle->db, handle->cf, &txn);
    handle->txn = txn;

    return tidesdb_iter_new(txn, (tidesdb_iter_t **)iter);
}

static int tidesdb_iter_seek_to_first_impl(void *iter)
{
    return tidesdb_iter_seek_to_first((tidesdb_iter_t *)iter);
}

static int tidesdb_iter_valid_impl(void *iter)
{
    return tidesdb_iter_valid((tidesdb_iter_t *)iter);
}

static int tidesdb_iter_next_impl(void *iter)
{
    return tidesdb_iter_next((tidesdb_iter_t *)iter);
}

static int tidesdb_iter_key_impl(void *iter, uint8_t **key, size_t *key_size)
{
    return tidesdb_iter_key((tidesdb_iter_t *)iter, key, key_size);
}

static int tidesdb_iter_value_impl(void *iter, uint8_t **value, size_t *value_size)
{
    return tidesdb_iter_value((tidesdb_iter_t *)iter, value, value_size);
}

static int tidesdb_iter_free_impl(void *iter)
{
    tidesdb_iter_free((tidesdb_iter_t *)iter);
    return 0;
}

static const storage_engine_ops_t tidesdb_ops = {
    .open = tidesdb_open_impl,
    .close = tidesdb_close_impl,
    .put = tidesdb_put_impl,
    .get = tidesdb_get_impl,
    .del = tidesdb_del_impl,
    .iter_new = tidesdb_iter_new_impl,
    .iter_seek_to_first = tidesdb_iter_seek_to_first_impl,
    .iter_valid = tidesdb_iter_valid_impl,
    .iter_next = tidesdb_iter_next_impl,
    .iter_key = tidesdb_iter_key_impl,
    .iter_value = tidesdb_iter_value_impl,
    .iter_free = tidesdb_iter_free_impl,
    .name = "TidesDB"
};

const storage_engine_ops_t *get_tidesdb_ops(void)
{
    return &tidesdb_ops;
}