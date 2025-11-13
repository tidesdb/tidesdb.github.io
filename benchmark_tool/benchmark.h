#ifndef BENCHMARK_H
#define BENCHMARK_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef enum
{
    WORKLOAD_WRITE,
    WORKLOAD_READ,
    WORKLOAD_MIXED
} workload_type_t;

typedef struct
{
    const char *engine_name;
    int num_operations;
    int key_size;
    int value_size;
    int num_threads;
    int batch_size;
    const char *db_path;
    int compare_mode;
    const char *report_file;
    int sequential_keys;
    workload_type_t workload_type;
} benchmark_config_t;

typedef struct
{
    double duration_seconds;
    double ops_per_second;
    double avg_latency_us;
    double p50_latency_us;
    double p95_latency_us;
    double p99_latency_us;
    double min_latency_us;
    double max_latency_us;
} operation_stats_t;

typedef struct
{
    const char *engine_name;
    benchmark_config_t config;
    operation_stats_t put_stats;
    operation_stats_t get_stats;
    operation_stats_t delete_stats;
    operation_stats_t iteration_stats;
    size_t total_bytes_written;
    size_t total_bytes_read;
} benchmark_results_t;

/* Storage engine interface */
typedef struct storage_engine_t storage_engine_t;

typedef struct
{
    /* Initialize engine */
    int (*open)(storage_engine_t **engine, const char *path);
    
    /* Close engine */
    int (*close)(storage_engine_t *engine);
    
    /* Put operation */
    int (*put)(storage_engine_t *engine, const uint8_t *key, size_t key_size,
               const uint8_t *value, size_t value_size);
    
    /* Get operation */
    int (*get)(storage_engine_t *engine, const uint8_t *key, size_t key_size,
               uint8_t **value, size_t *value_size);
    
    /* Delete operation */
    int (*del)(storage_engine_t *engine, const uint8_t *key, size_t key_size);
    
    /* Iterator operations */
    int (*iter_new)(storage_engine_t *engine, void **iter);
    int (*iter_seek_to_first)(void *iter);
    int (*iter_valid)(void *iter);
    int (*iter_next)(void *iter);
    int (*iter_key)(void *iter, uint8_t **key, size_t *key_size);
    int (*iter_value)(void *iter, uint8_t **value, size_t *value_size);
    int (*iter_free)(void *iter);
    
    const char *name;
} storage_engine_ops_t;

struct storage_engine_t
{
    const storage_engine_ops_t *ops;
    void *handle;  /* Engine-specific handle */
};

/* Benchmark functions */
int run_benchmark(benchmark_config_t *config, benchmark_results_t **results);
void generate_report(FILE *fp, benchmark_results_t *results, benchmark_results_t *baseline);
void free_results(benchmark_results_t *results);

/* Engine registration */
const storage_engine_ops_t *get_engine_ops(const char *engine_name);

#endif /* BENCHMARK_H */