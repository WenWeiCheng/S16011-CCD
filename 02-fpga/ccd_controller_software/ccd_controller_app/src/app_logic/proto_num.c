/******************************************************************************
* @file proto_num.c
*
* 协议数字/集合解析与格式化实现（纯逻辑，可独立主机测试）。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/03 First release
* </pre>
******************************************************************************/
#include "proto_num.h"
#include <string.h>

/*****************************************************************************/
/**
* @brief  无符号十进制 → buf（不含 NUL），返回长度。
******************************************************************************/
u32 Proto_Utoa(char *buf, u32 v)
{
    char tmp[12];
    u32 n = 0U, i;

    do {
        tmp[n++] = (char)('0' + (v % 10U));
        v /= 10U;
    } while (v != 0U);
    for (i = 0U; i < n; i++) {
        buf[i] = tmp[n - 1U - i];
    }
    buf[n] = '\0';
    return n;
}

/*****************************************************************************/
/**
* @brief  有符号十进制 → buf（带负号），返回长度。
******************************************************************************/
u32 Proto_Itoa(char *buf, s32 v)
{
    u32 n = 0U;
    if (v < 0) {
        buf[n++] = '-';
        v = -v;
    }
    return n + Proto_Utoa(buf + n, (u32)v);
}

/*****************************************************************************/
/**
* @brief  十进制字符串 → s32；整串须合法。
******************************************************************************/
int Proto_ParseInt(const char *s, s32 *out)
{
    s32 v = 0;
    int neg = 0;
    const char *p = s;

    if (*p == '-') { neg = 1; p++; }
    else if (*p == '+') { p++; }
    if (*p == '\0') return -1;
    while (*p != '\0') {
        if (*p < '0' || *p > '9') return -1;
        v = v * 10 + (s32)(*p - '0');
        p++;
    }
    *out = neg ? -v : v;
    return 0;
}

/*****************************************************************************/
/**
* @brief  十进制字符串 → u32；整串须合法。
******************************************************************************/
int Proto_ParseUInt(const char *s, u32 *out)
{
    u32 v = 0;
    const char *p = s;
    if (*p == '\0') return -1;
    while (*p != '\0') {
        if (*p < '0' || *p > '9') return -1;
        v = v * 10U + (u32)(*p - '0');
        p++;
    }
    *out = v;
    return 0;
}

/*****************************************************************************/
/**
* @brief  十进制浮点字符串 → float；整串须合法（支持小数，无科学计数法）。
******************************************************************************/
int Proto_ParseFloat(const char *s, float *out)
{
    float v = 0.0f;
    float scale = 1.0f;
    int neg = 0, dot = 0;
    const char *p = s;

    if (*p == '-') { neg = 1; p++; }
    else if (*p == '+') { p++; }
    if (*p == '\0') return -1;
    while (*p != '\0') {
        if (*p == '.') {
            if (dot) return -1;
            dot = 1;
            p++;
            continue;
        }
        if (*p < '0' || *p > '9') return -1;
        if (dot) {
            scale *= 10.0f;
            v += (float)(*p - '0') / scale;
        } else {
            v = v * 10.0f + (float)(*p - '0');
        }
        p++;
    }
    *out = neg ? -v : v;
    return 0;
}

/*****************************************************************************/
/**
* @brief  定点小数格式化：dec 位小数（0..5），四舍五入，支持负数，避免 -0。
******************************************************************************/
void Proto_FmtFloat(char *buf, u32 cap, float v, int dec)
{
    long ip, fp, scale = 1L;
    u32 n = 0U;
    int i, neg = 0;

    if (dec < 0) dec = 0;
    if (dec > 5) dec = 5;
    for (i = 0; i < dec; i++) scale *= 10L;

    if (v < 0.0f) { neg = 1; v = -v; }
    ip = (long)v;
    if (dec > 0) {
        fp = (long)((v - (float)ip) * (float)scale + 0.5f);
        if (fp >= scale) { fp -= scale; ip++; }   /* 小数进位 */
    } else {
        fp = 0L;
    }

    if (neg && (ip != 0L || fp != 0L)) {
        buf[n++] = '-';
    }
    n += Proto_Utoa(buf + n, (u32)ip);
    if (dec > 0) {
        char tmp[8];
        u32 m, z;
        if (n + 1U < cap) buf[n++] = '.';
        m = Proto_Utoa(tmp, (u32)fp);
        for (z = m; z < (u32)dec; z++) {          /* 前补零 */
            if (n + 1U < cap) buf[n++] = '0';
        }
        for (z = 0U; z < m; z++) {
            if (n + 1U < cap) buf[n++] = tmp[z];
        }
    }
    if (n >= cap) n = cap - 1U;
    buf[n] = '\0';
}

/*****************************************************************************/
/**
* @brief  解析 "min:max:step"（int）。
******************************************************************************/
int Proto_ParseIntConstraint(const char *c, long *mn, long *mx, long *st)
{
    char seg[16];
    s32 a, b, d;
    const char *p1 = c, *p2;

    p2 = strchr(p1, ':');
    if (p2 == NULL || p2 == p1) return -1;
    memcpy(seg, p1, (size_t)(p2 - p1));
    seg[p2 - p1] = '\0';
    if (Proto_ParseInt(seg, &a) != 0) return -1;

    p1 = p2 + 1;
    p2 = strchr(p1, ':');
    if (p2 == NULL || p2 == p1) return -1;
    memcpy(seg, p1, (size_t)(p2 - p1));
    seg[p2 - p1] = '\0';
    if (Proto_ParseInt(seg, &b) != 0) return -1;

    p1 = p2 + 1;
    if (*p1 == '\0') return -1;
    if (Proto_ParseInt(p1, &d) != 0) return -1;

    if (b < a || d <= 0) return -1;
    *mn = a; *mx = b; *st = d;
    return 0;
}

/*****************************************************************************/
/**
* @brief  解析 "min:max:step"（float）。
******************************************************************************/
int Proto_ParseFloatConstraint(const char *c, float *mn, float *mx, float *st)
{
    char seg[16];
    float a, b, d;
    const char *p1 = c, *p2;

    p2 = strchr(p1, ':');
    if (p2 == NULL || p2 == p1) return -1;
    memcpy(seg, p1, (size_t)(p2 - p1));
    seg[p2 - p1] = '\0';
    if (Proto_ParseFloat(seg, &a) != 0) return -1;

    p1 = p2 + 1;
    p2 = strchr(p1, ':');
    if (p2 == NULL || p2 == p1) return -1;
    memcpy(seg, p1, (size_t)(p2 - p1));
    seg[p2 - p1] = '\0';
    if (Proto_ParseFloat(seg, &b) != 0) return -1;

    p1 = p2 + 1;
    if (*p1 == '\0') return -1;
    if (Proto_ParseFloat(p1, &d) != 0) return -1;

    if (b < a || d <= 0.0f) return -1;
    *mn = a; *mx = b; *st = d;
    return 0;
}

/*****************************************************************************/
/**
* @brief  约束串 "0:2.500:0.001" 的 step 小数位 → 输出精度。
******************************************************************************/
int Proto_StepDecimals(const char *constraint)
{
    const char *step = strrchr(constraint, ':');
    const char *dot;

    if (step == NULL) return 0;
    step++;
    dot = strchr(step, '.');
    if (dot == NULL) return 0;
    return (int)strlen(dot + 1);
}

/*****************************************************************************/
/**
* @brief  逗号分隔列表的项数。
******************************************************************************/
u32 Proto_CollCount(const char *list)
{
    u32 n = 1U;
    while ((list = strchr(list, ',')) != NULL) {
        n++;
        list++;
    }
    return n;
}

/*****************************************************************************/
/**
* @brief  取第 idx 个逗号分隔标签到 buf。
******************************************************************************/
int Proto_CollLabel(const char *list, u32 idx, char *buf, u32 cap)
{
    const char *p = list;
    u32 i, n;

    for (i = 0; i < idx; i++) {
        p = strchr(p, ',');
        if (p == NULL) return -1;
        p++;
    }
    n = 0U;
    while (p[n] != '\0' && p[n] != ',') n++;
    if (n >= cap) n = cap - 1U;
    memcpy(buf, p, n);
    buf[n] = '\0';
    return 0;
}

/*****************************************************************************/
/**
* @brief  匹配标签 → 集合索引。
******************************************************************************/
int Proto_ParseColl(const char *list, const char *tok, s32 *out)
{
    u32 i, cnt = Proto_CollCount(list);
    char buf[32];

    for (i = 0; i < cnt; i++) {
        if (Proto_CollLabel(list, i, buf, sizeof buf) == 0 &&
            strcmp(buf, tok) == 0) {
            *out = (s32)i;
            return 0;
        }
    }
    return -1;
}

/*****************************************************************************/
/**
* @brief  组过滤：tec_* 前缀匹配，否则精确匹配。
******************************************************************************/
int Proto_MatchGroup(const char *name, const char *group)
{
    u32 glen = (u32)strlen(group);
    if (glen > 0 && group[glen - 1] == '*') {
        return strncmp(name, group, glen - 1) == 0;
    }
    return strcmp(name, group) == 0;
}
