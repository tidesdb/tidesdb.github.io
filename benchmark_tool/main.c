/*
 * TidesDB Storage Engine Benchmarker
 * Pluggable interface for comparing storage engines
 */
#include "benchmark.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>

static void print_usage(const char *prog)
{
    printf("TidesDB Storage Engine Benchmarker\n\n");
    printf("Usage: %s [OPTIONS]\n\n", prog);
    printf("Options:\n");
    printf("  -e, --engine <name>       Storage engine to benchmark (tidesdb, rocksdb)\n");
    printf("  -o, --operations <num>    Number of operations (default: 100000)\n");
    printf("  -k, --key-size <bytes>    Key size in bytes (default: 16)\n");
    printf("  -v, --value-size <bytes>  Value size in bytes (default: 100)\n");
    printf("  -t, --threads <num>       Number of threads (default: 1)\n");
    printf("  -b, --batch-size <num>    Batch size for operations (default: 1)\n");
    printf("  -d, --db-path <path>      Database path (default: ./bench_db)\n");
    printf("  -c, --compare             Compare against RocksDB baseline\n");
    printf("  -r, --report <file>       Output report to file (default: stdout)\n");
    printf("  -s, --sequential          Use sequential keys instead of random\n");
    printf("  -w, --workload <type>     Workload type: write, read, mixed (default: mixed)\n");
    printf("  -h, --help                Show this help message\n\n");
    printf("Examples:\n");
    printf("  %s -e tidesdb -o 1000000 -k 16 -v 100\n", prog);
    printf("  %s -e tidesdb -c -o 500000 -t 4\n", prog);
    printf("  %s -e rocksdb -w write -o 1000000\n", prog);
}

int main(int argc, char **argv)
{
    benchmark_config_t config = {
        .engine_name = "tidesdb",
        .num_operations = 1000000,
        .key_size = 16,
        .value_size = 100,
        .num_threads = 1,
        .batch_size = 1,
        .db_path = "./bench_db",
        .compare_mode = 1,
        .report_file = NULL,
        .sequential_keys = 0,
        .workload_type = WORKLOAD_MIXED
    };

    static struct option long_options[] = {
        {"engine", required_argument, 0, 'e'},
        {"operations", required_argument, 0, 'o'},
        {"key-size", required_argument, 0, 'k'},
        {"value-size", required_argument, 0, 'v'},
        {"threads", required_argument, 0, 't'},
        {"batch-size", required_argument, 0, 'b'},
        {"db-path", required_argument, 0, 'd'},
        {"compare", no_argument, 0, 'c'},
        {"report", required_argument, 0, 'r'},
        {"sequential", no_argument, 0, 's'},
        {"workload", required_argument, 0, 'w'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };

    int opt;
    int option_index = 0;

    while ((opt = getopt_long(argc, argv, "e:o:k:v:t:b:d:cr:sw:h", long_options, &option_index)) != -1)
    {
        switch (opt)
        {
            case 'e':
                config.engine_name = optarg;
                break;
            case 'o':
                config.num_operations = atoi(optarg);
                break;
            case 'k':
                config.key_size = atoi(optarg);
                break;
            case 'v':
                config.value_size = atoi(optarg);
                break;
            case 't':
                config.num_threads = atoi(optarg);
                break;
            case 'b':
                config.batch_size = atoi(optarg);
                break;
            case 'd':
                config.db_path = optarg;
                break;
            case 'c':
                config.compare_mode = 1;
                break;
            case 'r':
                config.report_file = optarg;
                break;
            case 's':
                config.sequential_keys = 1;
                break;
            case 'w':
                if (strcmp(optarg, "write") == 0)
                    config.workload_type = WORKLOAD_WRITE;
                else if (strcmp(optarg, "read") == 0)
                    config.workload_type = WORKLOAD_READ;
                else if (strcmp(optarg, "mixed") == 0)
                    config.workload_type = WORKLOAD_MIXED;
                else
                {
                    fprintf(stderr, "Invalid workload type: %s\n", optarg);
                    return 1;
                }
                break;
            case 'h':
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }

    /* Validate configuration */
    if (config.num_operations <= 0 || config.key_size <= 0 || config.value_size <= 0 ||
        config.num_threads <= 0 || config.batch_size <= 0)
    {
        fprintf(stderr, "Error: All numeric parameters must be positive\n");
        return 1;
    }

    /* Run benchmark */
    printf("=== TidesDB Storage Engine Benchmarker ===\n\n");
    printf("Configuration:\n");
    printf("  Engine: %s\n", config.engine_name);
    printf("  Operations: %d\n", config.num_operations);
    printf("  Key Size: %d bytes\n", config.key_size);
    printf("  Value Size: %d bytes\n", config.value_size);
    printf("  Threads: %d\n", config.num_threads);
    printf("  Batch Size: %d\n", config.batch_size);
    printf("  Key Pattern: %s\n", config.sequential_keys ? "Sequential" : "Random");
    printf("  Workload: %s\n", 
           config.workload_type == WORKLOAD_WRITE ? "Write-only" :
           config.workload_type == WORKLOAD_READ ? "Read-only" : "Mixed");
    printf("\n");

    benchmark_results_t *results = NULL;
    benchmark_results_t *baseline_results = NULL;

    /* Run primary benchmark */
    if (run_benchmark(&config, &results) != 0)
    {
        fprintf(stderr, "Benchmark failed\n");
        return 1;
    }

    /* Run comparison if requested */
    if (config.compare_mode && strcmp(config.engine_name, "rocksdb") != 0)
    {
        printf("\n=== Running RocksDB Baseline ===\n\n");
        benchmark_config_t baseline_config = config;
        baseline_config.engine_name = "rocksdb";
        
        if (run_benchmark(&baseline_config, &baseline_results) != 0)
        {
            fprintf(stderr, "Baseline benchmark failed\n");
        }
    }

    /* Generate report */
    FILE *report_fp = stdout;
    if (config.report_file)
    {
        report_fp = fopen(config.report_file, "w");
        if (!report_fp)
        {
            fprintf(stderr, "Failed to open report file: %s\n", config.report_file);
            report_fp = stdout;
        }
    }

    generate_report(report_fp, results, baseline_results);

    if (report_fp != stdout)
    {
        fclose(report_fp);
        printf("\nReport written to: %s\n", config.report_file);
    }

    /* Cleanup */
    free_results(results);
    if (baseline_results) free_results(baseline_results);

    return 0;
}