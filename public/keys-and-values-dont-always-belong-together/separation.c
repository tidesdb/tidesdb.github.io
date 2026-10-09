#include <tidesdb/db.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define KEYS        250000
#define VALUE_SIZE  4096
#define READS       100000
#define KEY_SIZE    16

static double now_s(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int cmp_u64(const void *a, const void *b)
{
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return x < y ? -1 : x > y;
}

static uint32_t *shuffled(uint32_t n, unsigned seed)
{
    uint32_t *order = malloc(n * sizeof(*order));
    for (uint32_t i = 0; i < n; i++) order[i] = i;
    srand(seed);
    for (uint32_t i = n - 1; i > 0; i--)
    {
        uint32_t j = (uint32_t)rand() % (i + 1), t = order[i];
        order[i] = order[j];
        order[j] = t;
    }
    return order;
}

static void put(tidesdb_t *db, tidesdb_column_family_t *cf, uint32_t id, uint8_t *value)
{
    char key[KEY_SIZE + 1];
    snprintf(key, sizeof(key), "key%013u", id);
    memcpy(value, &id, sizeof(id)); 
    tidesdb_txn_t *txn = NULL;
    tidesdb_txn_begin(db, &txn);
    tidesdb_txn_put(txn, cf, (uint8_t *)key, KEY_SIZE, value, VALUE_SIZE, 0);
    tidesdb_txn_commit(txn);
    tidesdb_txn_free(txn);
}

static void settle(tidesdb_t *db, tidesdb_column_family_t *cf)
{
    tidesdb_flush_memtable(db);
    while (tidesdb_is_flushing(db) || tidesdb_is_compacting(cf)) usleep(100 * 1000);
}

int main(int argc, char **argv)
{
    if (argc != 3) return fprintf(stderr, "usage: %s separate|inline|inline64k dir\n", argv[0]), 2;

    const int big_nodes = strcmp(argv[1], "inline64k") == 0;
    const int inline_values = big_nodes || strcmp(argv[1], "inline") == 0;

    tidesdb_config_t config = tidesdb_default_config();
    config.db_path = argv[2];
    config.log_level = TDB_LOG_NONE;
    tidesdb_t *db = NULL;
    if (tidesdb_open(&config, &db) != TDB_SUCCESS) return 1;

    tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
    cf_config.keep_values_inline = inline_values;
    if (big_nodes) cf_config.btree_klog_block_size = 64 * 1024;
    tidesdb_create_column_family(db, "t", &cf_config);
    tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "t");

    uint8_t *value = malloc(VALUE_SIZE);
    srand(7);
    for (int i = 0; i < VALUE_SIZE; i++) value[i] = (uint8_t)rand();

    uint32_t *load = shuffled(KEYS, 1), *update = shuffled(KEYS, 2);
    const double w0 = now_s();
    for (uint32_t i = 0; i < KEYS; i++) put(db, cf, load[i], value);
    for (uint32_t i = 0; i < KEYS; i++) put(db, cf, update[i], value);
    const double write_s = now_s() - w0;
    settle(db, cf);
    const double settled_s = now_s() - w0;

    tidesdb_db_stats_t st;
    tidesdb_get_db_stats(db, &st);
    const double user = (double)st.user_bytes_written;
    const double device = (double)(st.wal_bytes_written + st.vlog_bytes_written +
                                   st.flush_bytes_written + st.compaction_bytes_written);

    uint64_t *lat = malloc(READS * sizeof(*lat));
    uint32_t *reads = shuffled(KEYS, 3);
    for (uint32_t i = 0; i < READS; i++)
    {
        char key[KEY_SIZE + 1];
        snprintf(key, sizeof(key), "key%013u", reads[i]);
        uint8_t *v = NULL;
        size_t vs = 0;
        const double r0 = now_s();
        tidesdb_txn_t *txn = NULL;
        tidesdb_txn_begin(db, &txn);
        if (tidesdb_txn_get(txn, cf, (uint8_t *)key, KEY_SIZE, &v, &vs) != TDB_SUCCESS) return 3;
        tidesdb_txn_free(txn);
        lat[i] = (uint64_t)((now_s() - r0) * 1e9);
        tidesdb_free(v);
    }
    qsort(lat, READS, sizeof(*lat), cmp_u64);

    tidesdb_txn_t *txn = NULL;
    tidesdb_txn_begin(db, &txn);
    tidesdb_iter_t *it = NULL;
    tidesdb_iter_new(txn, cf, &it);
    uint64_t rows = 0;
    const double s0 = now_s();
    for (tidesdb_iter_seek_to_first(it); tidesdb_iter_valid(it); tidesdb_iter_next(it))
    {
        uint8_t *k = NULL, *v = NULL;
        size_t ks = 0, vs = 0;
        tidesdb_iter_key_value(it, &k, &ks, &v, &vs);
        tidesdb_free(k);
        tidesdb_free(v);
        rows++;
    }
    const double scan_s = now_s() - s0;
    tidesdb_iter_free(it);
    tidesdb_txn_free(txn);

    printf("%-8s writes %.0f/s (%.1fs, %.1fs to settle)  write amp %.2f  compaction wrote %.0f MB  "
           "on disk %.0f MB\n",
           argv[1], 2.0 * KEYS / write_s, write_s, settled_s, device / user,
           st.compaction_bytes_written / 1e6,
           (st.total_data_size_bytes + st.vlog_file_size) / 1e6);
    printf("%-8s get p50 %.1fus p99 %.1fus max %.1fms  scan %lu rows in %.2fs\n", argv[1],
           lat[READS / 2] / 1e3, lat[READS * 99 / 100] / 1e3, lat[READS - 1] / 1e6,
           (unsigned long)rows, scan_s);

    tidesdb_compact(db, cf);
    settle(db, cf);
    uint64_t last = 0, size = 1;
    for (int i = 0; i < 100 && size != last; i++)
    {
        last = size;
        sleep(1);
        tidesdb_get_db_stats(db, &st);
        size = st.total_data_size_bytes + st.vlog_file_size;
    }
    printf("%-8s after compaction on disk %.0f MB\n", argv[1], size / 1e6);

    tidesdb_close(db);
    return 0;
}
