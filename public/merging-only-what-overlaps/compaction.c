#include <tidesdb/db.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define KEYS        6000000
#define VALUE_SIZE  160
#define KEY_SIZE    16
#define BATCH       64
#define SAMPLE      250000
#define BUFFER      (4u << 20)

static double t0;

static double now_s(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static uint32_t *shuffled(uint32_t n, unsigned seed)
{
    uint32_t *order = malloc(n * sizeof(*order));
    for (uint32_t i = 0; i < n; i++) order[i] = i;
    srand(seed);
    for (uint32_t i = n - 1; i > 0; i--)
    {
        uint32_t j = (uint32_t)(((uint64_t)rand() << 16 ^ rand()) % (i + 1)), t = order[i];
        order[i] = order[j];
        order[j] = t;
    }
    return order;
}

static void sample(const char *phase, tidesdb_column_family_t *cf)
{
    tidesdb_cf_stats_t s;
    tidesdb_get_cf_stats(cf, &s);
    printf("S %s %.1f %.1f %d %.1f", phase, now_s() - t0, s.user_bytes_written / 1e6, s.num_levels,
           s.read_amp);
    for (int i = 0; i < s.num_levels; i++) printf(" %.1f", s.level_sizes[i] / 1e6);
    printf("\n");
    fflush(stdout);
}

static void write_keys(tidesdb_t *db, tidesdb_column_family_t *cf, const uint32_t *ids, uint32_t n,
                       const uint8_t *value, const char *phase)
{
    for (uint32_t i = 0; i < n; i += BATCH)
    {
        tidesdb_txn_t *txn = NULL;
        tidesdb_txn_begin(db, &txn);
        for (uint32_t j = i; j < i + BATCH && j < n; j++)
        {
            char key[KEY_SIZE + 1];
            snprintf(key, sizeof(key), "key%013u", ids[j]);
            if (value)
                tidesdb_txn_put(txn, cf, (uint8_t *)key, KEY_SIZE, value, VALUE_SIZE, 0);
            else
                tidesdb_txn_delete(txn, cf, (uint8_t *)key, KEY_SIZE);
        }
        tidesdb_txn_commit(txn);
        tidesdb_txn_free(txn);
        if ((i / BATCH) % (SAMPLE / BATCH) == 0) sample(phase, cf);
    }
}

static void settle(tidesdb_t *db, tidesdb_column_family_t *cf, const char *phase)
{
    tidesdb_flush_memtable(db);
    uint64_t last = UINT64_MAX;
    int quiet = 0;
    while (quiet < 10)
    {
        usleep(500 * 1000);
        sample(phase, cf);
        tidesdb_cf_stats_t s;
        tidesdb_get_cf_stats(cf, &s);
        quiet = (s.compaction_count == last && !tidesdb_is_flushing(db) &&
                 !tidesdb_is_compacting(cf)) ? quiet + 1 : 0;
        last = s.compaction_count;
    }
}

int main(int argc, char **argv)
{
    if (argc != 5) return fprintf(stderr, "usage: %s offset threads random|sequential dir\n", argv[0]), 2;
    const int sequential = strcmp(argv[3], "sequential") == 0;

    tidesdb_config_t config = tidesdb_default_config();
    config.db_path = argv[4];
    config.log_level = TDB_LOG_INFO;
    config.log_to_file = 1;
    config.memtable_write_buffer_size = BUFFER;
    config.num_compaction_threads = atoi(argv[2]);
    tidesdb_t *db = NULL;
    if (tidesdb_open(&config, &db) != TDB_SUCCESS) return 1;

    tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
    cf_config.dividing_level_offset = atoi(argv[1]);
    tidesdb_create_column_family(db, "t", &cf_config);
    tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "t");

    uint8_t value[VALUE_SIZE];
    srand(7);
    for (int i = 0; i < VALUE_SIZE; i++) value[i] = (uint8_t)rand();

    t0 = now_s();
    uint32_t *load = shuffled(KEYS, 1);
    if (sequential)
        for (uint32_t i = 0; i < KEYS; i++) load[i] = i;
    write_keys(db, cf, load, KEYS, value, "load");
    const double load_s = now_s() - t0;
    settle(db, cf, "load");

    tidesdb_cf_stats_t s;
    tidesdb_get_cf_stats(cf, &s);
    printf("R load %.1fs settled %.1fs user %.0f MB flush %.0f MB compaction %.0f MB read %.0f MB "
           "write amp %.2f merges %lu read amp %.1f levels %d\n",
           load_s, now_s() - t0, s.user_bytes_written / 1e6, s.flush_bytes_written / 1e6,
           s.compaction_bytes_written / 1e6, s.compaction_bytes_read / 1e6,
           (double)(s.flush_bytes_written + s.compaction_bytes_written) / s.user_bytes_written,
           (unsigned long)s.compaction_count, s.read_amp, s.num_levels);

    uint32_t *gone = shuffled(KEYS, 2);
    write_keys(db, cf, gone, KEYS / 10 * 9, NULL, "delete");
    settle(db, cf, "delete");
    for (int i = 0; i < 6; i++)
    {
        tidesdb_compact(db, cf);
        settle(db, cf, "delete");
    }
    tidesdb_get_cf_stats(cf, &s);
    printf("R delete levels %d read amp %.1f on disk %.0f MB\n", s.num_levels, s.read_amp,
           s.total_data_size / 1e6);

    tidesdb_close(db);
    free(load);
    free(gone);
    return 0;
}
