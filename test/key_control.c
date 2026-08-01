#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <string.h>

// GPIO配置结构体
struct gpio_config {
    int number;         // GPIO编号
    int value_fd;       // 值文件描述符
    char prev_value;    // 前一个状态值
    const char *name;   // 按钮名称（可选）
};

// 要监控的GPIO列表
struct gpio_config gpios[] = {
    {47, -1, '1', "按钮1"},
    {48, -1, '1', "按钮2"},
};
#define GPIO_COUNT (sizeof(gpios)/sizeof(gpios[0]))

volatile sig_atomic_t stop = 0;

void handle_signal(int sig) {
    stop = 1;
}

// 初始化单个GPIO
int init_gpio(struct gpio_config *gpio) {
    char path[128];
    
    // 导出GPIO
    FILE *export = fopen("/sys/class/gpio/export", "w");
    if (!export) {
        perror("导出GPIO失败");
        return -1;
    }
    fprintf(export, "%d", gpio->number);
    fclose(export);

    // 等待目录创建
    usleep(100000);

    // 设置输入模式
    snprintf(path, sizeof(path), "/sys/class/gpio/gpio%d/direction", gpio->number);
    FILE *direction = fopen(path, "w");
    if (!direction) {
        perror("设置方向失败");
        return -1;
    }
    fprintf(direction, "in");
    fclose(direction);

    // 打开值文件
    snprintf(path, sizeof(path), "/sys/class/gpio/gpio%d/value", gpio->number);
    gpio->value_fd = open(path, O_RDONLY);
    if (gpio->value_fd < 0) {
        perror("打开值文件失败");
        return -1;
    }

    return 0;
}

// 清理单个GPIO
void cleanup_gpio(struct gpio_config *gpio) {
    if (gpio->value_fd != -1) {
        close(gpio->value_fd);
        gpio->value_fd = -1;
    }

    // 取消导出
    FILE *unexport = fopen("/sys/class/gpio/unexport", "w");
    if (unexport) {
        fprintf(unexport, "%d", gpio->number);
        fclose(unexport);
    }
}

int main() {
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    // 初始化所有GPIO
    for (int i = 0; i < GPIO_COUNT; i++) {
        if (init_gpio(&gpios[i]) != 0) {
            fprintf(stderr, "初始化GPIO%d失败，跳过\n", gpios[i].number);
            gpios[i].value_fd = -1;  // 标记为无效
        }
    }

    printf("监控多个GPIO按钮... (Ctrl+C退出)\n");

    while (!stop) {
        for (int i = 0; i < GPIO_COUNT; i++) {
            struct gpio_config *g = &gpios[i];
            
            if (g->value_fd == -1) continue;  // 跳过初始化失败的GPIO

            char current_value;
            lseek(g->value_fd, 0, SEEK_SET);
            read(g->value_fd, &current_value, 1);

            // 检测下降沿（1 -> 0）
            if (g->prev_value == '1' && current_value == '0') {
                printf("%s（GPIO%d）触发：正常\n", g->name, g->number);
                fflush(stdout);
            }
            g->prev_value = current_value;
        }
        usleep(10000);  // 10ms间隔
    }

    // 清理所有GPIO
    for (int i = 0; i < GPIO_COUNT; i++) {
        cleanup_gpio(&gpios[i]);
    }

    return 0;
}