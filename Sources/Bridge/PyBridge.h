#ifndef PyBridge_h
#define PyBridge_h

#pragma clang assume_nonnull begin

typedef void (*ide_out_cb)(int stream, const char * _Nullable text);
typedef char * _Nullable (*ide_in_cb)(const char * _Nullable prompt);

int ide_py_init(const char *home, const char *executable, const char *libdir,
                const char *bootstrap, ide_out_cb out, ide_in_cb inp,
                char *err, int errlen);
void ide_py_run(const char *code, const char *name);
void ide_py_repl(const char *line);
void ide_py_interrupt(void);

#pragma clang assume_nonnull end

#endif
