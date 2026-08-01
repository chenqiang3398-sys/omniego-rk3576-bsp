#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define GPIO_PATH "/sys/class/gpio"
#define GPIO_VALUE "value"
#define GPIO_DIRECTION "direction"
#define GPIO_EXPORT "export"
#define GPIO_UNEXPORT "unexport"

void setup_gpio(int pin, const char *direction) {
    char path[64];

    // Export GPIO
    snprintf(path, sizeof(path), "%s/%s", GPIO_PATH, GPIO_EXPORT);
    FILE *export_file = fopen(path, "w");
    if (!export_file) {
        perror("Failed to open export file");
        exit(EXIT_FAILURE);
    }
    fprintf(export_file, "%d", pin);
    fclose(export_file);

    // Set direction
    snprintf(path, sizeof(path), "%s/gpio%d/%s", GPIO_PATH, pin, GPIO_DIRECTION);
    FILE *direction_file = fopen(path, "w");
    if (!direction_file) {
        perror("Failed to open direction file");
        exit(EXIT_FAILURE);
    }
    fprintf(direction_file, "%s", direction);
    fclose(direction_file);
}

void set_gpio_value(int pin, int value) {
    char path[64];

    snprintf(path, sizeof(path), "%s/gpio%d/%s", GPIO_PATH, pin, GPIO_VALUE);
    FILE *value_file = fopen(path, "w");
    if (!value_file) {
        perror("Failed to open value file");
        exit(EXIT_FAILURE);
    }
    fprintf(value_file, "%d", value);
    fclose(value_file);
}

void cleanup_gpio(int pin) {
    char path[64];

    snprintf(path, sizeof(path), "%s/%s", GPIO_PATH, GPIO_UNEXPORT);
    FILE *unexport_file = fopen(path, "w");
    if (!unexport_file) {
        perror("Failed to open unexport file");
        exit(EXIT_FAILURE);
    }
    fprintf(unexport_file, "%d", pin);
    fclose(unexport_file);
}

int main() {
    int pins[] = {19, 24, 13, 126};
    int num_pins = sizeof(pins) / sizeof(pins[0]);
    int i;

    // Set up GPIOs as outputs
    for (i = 0; i < num_pins; i++) {
        setup_gpio(pins[i], "out");
    }

    // Turn off GPIOs
    for (i = 0; i < num_pins; i++) {
        set_gpio_value(pins[i], 0);
    }

    // Sleep for 5 seconds
    sleep(5);

    // Turn on GPIOs
    for (i = 0; i < num_pins; i++) {
        set_gpio_value(pins[i], 1);
    }

    // Clean up GPIOs
    for (i = 0; i < num_pins; i++) {
        cleanup_gpio(pins[i]);
    }

    return 0;
}