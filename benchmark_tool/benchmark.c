#include "benchmark.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <pthread.h>
#include <math.h>

typedef struct
{
    benchmark_config_t *config;
    storage_engine_t *engine;
    int thread_id;
    int ops_per_thread;
    double *latencies;
    int latency_count;
} thread_context_t;

static double get_time_microseconds(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000000.0 + tv.tv_usec;
}

static void generate_key(uint8_t *key, size_t key_size, int index, int sequential)
{
    if (sequential)
    {
        /* Format: "key" + padded number that fits in key_size */
        snprintf((char *)key, key_size, "key%0*d", (int)(key_size - 4), index);
    }
    else
    {
        /* Random key based on index */
        uint64_t hash = index * 2654435761ULL;
        snprintf((char *)key, key_size, "key%0*llx", (int)(key_size - 4), (unsigned long long)hash);
    }
}

static void generate_value(uint8_t *value, size_t value_size, int index)
{
    for (size_t i = 0; i < value_size; i++)
    {
        value[i] = (uint8_t)((index + i) % 256);
    }
}

static int compare_double(const void *a, const void *b)
{
    double da = *(const double *)a;
    double db = *(const double *)b;
    return (da > db) - (da < db);
}

static void calculate_stats(double *latencies, int count, operation_stats_t *stats)
{
    if (count == 0) return;
    
    qsort(latencies, count, sizeof(double), compare_double);
    
    double sum = 0.0;
    stats->min_latency_us = latencies[0];
    stats->max_latency_us = latencies[count - 1];
    
    for (int i = 0; i < count; i++)
    {
        sum += latencies[i];
    }
    
    stats->avg_latency_us = sum / count;
    stats->p50_latency_us = latencies[(int)(count * 0.50)];
    stats->p95_latency_us = latencies[(int)(count * 0.95)];
    stats->p99_latency_us = latencies[(int)(count * 0.99)];
}

static void *benchmark_put_thread(void *arg)
{
    thread_context_t *ctx = (thread_context_t *)arg;
    uint8_t *key = malloc(ctx->config->key_size);
    uint8_t *value = malloc(ctx->config->value_size);
    
    ctx->latencies = malloc(ctx->ops_per_thread * sizeof(double));
    ctx->latency_count = 0;
    
    int start_index = ctx->thread_id * ctx->ops_per_thread;
    
    for (int i = 0; i < ctx->ops_per_thread; i++)
    {
        generate_key(key, ctx->config->key_size, start_index + i, ctx->config->sequential_keys);
        generate_value(value, ctx->config->value_size, start_index + i);
        
        double start = get_time_microseconds();
        ctx->engine->ops->put(ctx->engine, key, ctx->config->key_size, 
                              value, ctx->config->value_size);
        double end = get_time_microseconds();
        
        ctx->latencies[ctx->latency_count++] = end - start;
    }
    
    free(key);
    free(value);
    return NULL;
}

static void *benchmark_get_thread(void *arg)
{
    thread_context_t *ctx = (thread_context_t *)arg;
    uint8_t *key = malloc(ctx->config->key_size);
    
    ctx->latencies = malloc(ctx->ops_per_thread * sizeof(double));
    ctx->latency_count = 0;
    
    int start_index = ctx->thread_id * ctx->ops_per_thread;
    
    for (int i = 0; i < ctx->ops_per_thread; i++)
    {
        generate_key(key, ctx->config->key_size, start_index + i, ctx->config->sequential_keys);
        
        uint8_t *value = NULL;
        size_t value_size = 0;
        
        double start = get_time_microseconds();
        ctx->engine->ops->get(ctx->engine, key, ctx->config->key_size, &value, &value_size);
        double end = get_time_microseconds();
        
        if (value) free(value);
        ctx->latencies[ctx->latency_count++] = end - start;
    }
    
    free(key);
    return NULL;
}

static void *benchmark_delete_thread(void *arg)
{
    thread_context_t *ctx = (thread_context_t *)arg;
    uint8_t *key = malloc(ctx->config->key_size);
    
    ctx->latencies = malloc(ctx->ops_per_thread * sizeof(double));
    ctx->latency_count = 0;
    
    int start_index = ctx->thread_id * ctx->ops_per_thread;
    
    for (int i = 0; i < ctx->ops_per_thread; i++)
    {
        generate_key(key, ctx->config->key_size, start_index + i, ctx->config->sequential_keys);
        
        double start = get_time_microseconds();
        ctx->engine->ops->del(ctx->engine, key, ctx->config->key_size);
        double end = get_time_microseconds();
        
        ctx->latencies[ctx->latency_count++] = end - start;
    }
    
    free(key);
    return NULL;
}

int run_benchmark(benchmark_config_t *config, benchmark_results_t **results)
{
    *results = calloc(1, sizeof(benchmark_results_t));
    if (!*results) return -1;
    
    (*results)->engine_name = config->engine_name;
    (*results)->config = *config;
    
    /* Get engine operations */
    const storage_engine_ops_t *ops = get_engine_ops(config->engine_name);
    if (!ops)
    {
        fprintf(stderr, "Unknown engine: %s\n", config->engine_name);
        free(*results);
        return -1;
    }
    
    /* Open engine */
    storage_engine_t *engine = NULL;
    if (ops->open(&engine, config->db_path) != 0)
    {
        fprintf(stderr, "Failed to open engine\n");
        free(*results);
        return -1;
    }
    
    printf("Running %s benchmark...\n", ops->name);
    
    /* Benchmark PUT operations */
    if (config->workload_type == WORKLOAD_WRITE || config->workload_type == WORKLOAD_MIXED)
    {
        printf("  PUT: ");
        fflush(stdout);
        
        pthread_t *threads = malloc(config->num_threads * sizeof(pthread_t));
        thread_context_t *contexts = calloc(config->num_threads, sizeof(thread_context_t));
        
        int ops_per_thread = config->num_operations / config->num_threads;
        double start_time = get_time_microseconds();
        
        for (int i = 0; i < config->num_threads; i++)
        {
            contexts[i].config = config;
            contexts[i].engine = engine;
            contexts[i].thread_id = i;
            contexts[i].ops_per_thread = ops_per_thread;
            pthread_create(&threads[i], NULL, benchmark_put_thread, &contexts[i]);
        }
        
        for (int i = 0; i < config->num_threads; i++)
        {
            pthread_join(threads[i], NULL);
        }
        
        double end_time = get_time_microseconds();
        (*results)->put_stats.duration_seconds = (end_time - start_time) / 1000000.0;
        (*results)->put_stats.ops_per_second = config->num_operations / (*results)->put_stats.duration_seconds;
        
        /* Aggregate latencies */
        int total_latencies = 0;
        for (int i = 0; i < config->num_threads; i++)
        {
            total_latencies += contexts[i].latency_count;
        }
        
        double *all_latencies = malloc(total_latencies * sizeof(double));
        int offset = 0;
        for (int i = 0; i < config->num_threads; i++)
        {
            memcpy(all_latencies + offset, contexts[i].latencies, 
                   contexts[i].latency_count * sizeof(double));
            offset += contexts[i].latency_count;
            free(contexts[i].latencies);
        }
        
        calculate_stats(all_latencies, total_latencies, &(*results)->put_stats);
        free(all_latencies);
        free(threads);
        free(contexts);
        
        (*results)->total_bytes_written = (size_t)config->num_operations * 
                                          (config->key_size + config->value_size);
        
        printf("%.2f ops/sec\n", (*results)->put_stats.ops_per_second);
    }
    
    /* Benchmark GET operations */
    if (config->workload_type == WORKLOAD_READ || config->workload_type == WORKLOAD_MIXED)
    {
        printf("  GET: ");
        fflush(stdout);
        
        pthread_t *threads = malloc(config->num_threads * sizeof(pthread_t));
        thread_context_t *contexts = calloc(config->num_threads, sizeof(thread_context_t));
        
        int ops_per_thread = config->num_operations / config->num_threads;
        double start_time = get_time_microseconds();
        
        for (int i = 0; i < config->num_threads; i++)
        {
            contexts[i].config = config;
            contexts[i].engine = engine;
            contexts[i].thread_id = i;
            contexts[i].ops_per_thread = ops_per_thread;
            pthread_create(&threads[i], NULL, benchmark_get_thread, &contexts[i]);
        }
        
        for (int i = 0; i < config->num_threads; i++)
        {
            pthread_join(threads[i], NULL);
        }
        
        double end_time = get_time_microseconds();
        (*results)->get_stats.duration_seconds = (end_time - start_time) / 1000000.0;
        (*results)->get_stats.ops_per_second = config->num_operations / (*results)->get_stats.duration_seconds;
        
        /* Aggregate latencies */
        int total_latencies = 0;
        for (int i = 0; i < config->num_threads; i++)
        {
            total_latencies += contexts[i].latency_count;
        }
        
        double *all_latencies = malloc(total_latencies * sizeof(double));
        int offset = 0;
        for (int i = 0; i < config->num_threads; i++)
        {
            memcpy(all_latencies + offset, contexts[i].latencies, 
                   contexts[i].latency_count * sizeof(double));
            offset += contexts[i].latency_count;
            free(contexts[i].latencies);
        }
        
        calculate_stats(all_latencies, total_latencies, &(*results)->get_stats);
        free(all_latencies);
        free(threads);
        free(contexts);
        
        (*results)->total_bytes_read = (size_t)config->num_operations * config->value_size;
        
        printf("%.2f ops/sec\n", (*results)->get_stats.ops_per_second);
    }
    
    /* Benchmark iteration */
    printf("  ITER: ");
    fflush(stdout);
    
    void *iter = NULL;
    if (engine->ops->iter_new(engine, &iter) == 0)
    {
        double start_time = get_time_microseconds();
        int count = 0;
        
        engine->ops->iter_seek_to_first(iter);
        while (engine->ops->iter_valid(iter))
        {
            uint8_t *key = NULL, *value = NULL;
            size_t key_size = 0, value_size = 0;
            engine->ops->iter_key(iter, &key, &key_size);
            engine->ops->iter_value(iter, &value, &value_size);
            engine->ops->iter_next(iter);
            count++;
        }
        
        double end_time = get_time_microseconds();
        (*results)->iteration_stats.duration_seconds = (end_time - start_time) / 1000000.0;
        if (count > 0)
        {
            (*results)->iteration_stats.ops_per_second = count / (*results)->iteration_stats.duration_seconds;
        }
        
        engine->ops->iter_free(iter);
        printf("%.2f ops/sec (%d keys)\n", (*results)->iteration_stats.ops_per_second, count);
    }
    else
    {
        printf("not supported\n");
    }
    
    ops->close(engine);
    return 0;
}

void generate_report(FILE *fp, benchmark_results_t *results, benchmark_results_t *baseline)
{
    fprintf(fp, "\n=== Benchmark Results ===\n\n");
    fprintf(fp, "Engine: %s\n", results->engine_name);
    fprintf(fp, "Operations: %d\n", results->config.num_operations);
    fprintf(fp, "Threads: %d\n", results->config.num_threads);
    fprintf(fp, "Key Size: %d bytes\n", results->config.key_size);
    fprintf(fp, "Value Size: %d bytes\n\n", results->config.value_size);
    
    if (results->put_stats.ops_per_second > 0)
    {
        fprintf(fp, "PUT Operations:\n");
        fprintf(fp, "  Throughput: %.2f ops/sec\n", results->put_stats.ops_per_second);
        fprintf(fp, "  Duration: %.3f seconds\n", results->put_stats.duration_seconds);
        fprintf(fp, "  Latency (avg): %.2f μs\n", results->put_stats.avg_latency_us);
        fprintf(fp, "  Latency (p50): %.2f μs\n", results->put_stats.p50_latency_us);
        fprintf(fp, "  Latency (p95): %.2f μs\n", results->put_stats.p95_latency_us);
        fprintf(fp, "  Latency (p99): %.2f μs\n", results->put_stats.p99_latency_us);
        fprintf(fp, "  Latency (min): %.2f μs\n", results->put_stats.min_latency_us);
        fprintf(fp, "  Latency (max): %.2f μs\n\n", results->put_stats.max_latency_us);
    }
    
    if (results->get_stats.ops_per_second > 0)
    {
        fprintf(fp, "GET Operations:\n");
        fprintf(fp, "  Throughput: %.2f ops/sec\n", results->get_stats.ops_per_second);
        fprintf(fp, "  Duration: %.3f seconds\n", results->get_stats.duration_seconds);
        fprintf(fp, "  Latency (avg): %.2f μs\n", results->get_stats.avg_latency_us);
        fprintf(fp, "  Latency (p50): %.2f μs\n", results->get_stats.p50_latency_us);
        fprintf(fp, "  Latency (p95): %.2f μs\n", results->get_stats.p95_latency_us);
        fprintf(fp, "  Latency (p99): %.2f μs\n", results->get_stats.p99_latency_us);
        fprintf(fp, "  Latency (min): %.2f μs\n", results->get_stats.min_latency_us);
        fprintf(fp, "  Latency (max): %.2f μs\n\n", results->get_stats.max_latency_us);
    }
    
    if (results->iteration_stats.ops_per_second > 0)
    {
        fprintf(fp, "ITERATION:\n");
        fprintf(fp, "  Throughput: %.2f ops/sec\n", results->iteration_stats.ops_per_second);
        fprintf(fp, "  Duration: %.3f seconds\n\n", results->iteration_stats.duration_seconds);
    }
    
    /* Comparison */
    if (baseline)
    {
        fprintf(fp, "=== Comparison vs %s ===\n\n", baseline->engine_name);
        
        if (results->put_stats.ops_per_second > 0 && baseline->put_stats.ops_per_second > 0)
        {
            double speedup = results->put_stats.ops_per_second / baseline->put_stats.ops_per_second;
            fprintf(fp, "PUT: %.2fx %s\n", speedup, speedup > 1.0 ? "faster" : "slower");
        }
        
        if (results->get_stats.ops_per_second > 0 && baseline->get_stats.ops_per_second > 0)
        {
            double speedup = results->get_stats.ops_per_second / baseline->get_stats.ops_per_second;
            fprintf(fp, "GET: %.2fx %s\n", speedup, speedup > 1.0 ? "faster" : "slower");
        }
        
        if (results->iteration_stats.ops_per_second > 0 && baseline->iteration_stats.ops_per_second > 0)
        {
            double speedup = results->iteration_stats.ops_per_second / baseline->iteration_stats.ops_per_second;
            fprintf(fp, "ITER: %.2fx %s\n", speedup, speedup > 1.0 ? "faster" : "slower");
        }
    }
}

void free_results(benchmark_results_t *results)
{
    if (results) free(results);
}