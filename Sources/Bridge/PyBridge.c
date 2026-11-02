#include <Python/Python.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "PyBridge.h"

static ide_out_cb g_out = NULL;
static ide_in_cb g_in = NULL;
static unsigned long g_run_thread = 0;
static PyObject *g_run_fn = NULL;
static PyObject *g_repl_fn = NULL;

static void set_err(char *err, int len, const char *msg) {
    if (err && len > 0) {
        strncpy(err, msg ? msg : "unknown error", (size_t)(len - 1));
        err[len - 1] = 0;
    }
}

static PyObject *bridge_write(PyObject *self, PyObject *args) {
    int stream;
    const char *text;
    if (!PyArg_ParseTuple(args, "is", &stream, &text)) return NULL;
    if (g_out) g_out(stream, text);
    Py_RETURN_NONE;
}

static PyObject *bridge_read(PyObject *self, PyObject *args) {
    const char *prompt;
    if (!PyArg_ParseTuple(args, "s", &prompt)) return NULL;
    char *line = NULL;
    if (g_in) {
        Py_BEGIN_ALLOW_THREADS
        line = g_in(prompt);
        Py_END_ALLOW_THREADS
    }
    if (!line) {
        PyErr_SetNone(PyExc_EOFError);
        return NULL;
    }
    PyObject *result = PyUnicode_FromString(line);
    free(line);
    return result;
}

static PyMethodDef bridge_methods[] = {
    {"write", bridge_write, METH_VARARGS, "write(stream, text)"},
    {"read", bridge_read, METH_VARARGS, "read(prompt) -> str"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef bridge_module = {
    PyModuleDef_HEAD_INIT, "_ide_bridge", NULL, -1, bridge_methods
};

static PyObject *PyInit__ide_bridge(void) {
    return PyModule_Create(&bridge_module);
}

int ide_py_init(const char *home, const char *executable, const char *libdir,
                const char *bootstrap, ide_out_cb out, ide_in_cb inp,
                char *err, int errlen) {
    g_out = out;
    g_in = inp;

    PyStatus status;
    PyPreConfig preconfig;
    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    status = Py_PreInitialize(&preconfig);
    if (PyStatus_Exception(status)) {
        set_err(err, errlen, status.err_msg);
        return -1;
    }

    if (PyImport_AppendInittab("_ide_bridge", PyInit__ide_bridge) == -1) {
        set_err(err, errlen, "could not register bridge module");
        return -2;
    }

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.write_bytecode = 0;
    config.buffered_stdio = 0;
    config.install_signal_handlers = 0;
    config.parse_argv = 0;

    status = PyConfig_SetBytesString(&config, &config.home, home);
    if (PyStatus_Exception(status)) goto fail;
    status = PyConfig_SetBytesString(&config, &config.executable, executable);
    if (PyStatus_Exception(status)) goto fail;
    status = PyConfig_SetBytesString(&config, &config.program_name, executable);
    if (PyStatus_Exception(status)) goto fail;

    config.module_search_paths_set = 1;
    {
        char dyn[4096];
        snprintf(dyn, sizeof(dyn), "%s/lib-dynload", libdir);
        const char *paths[2] = { libdir, dyn };
        for (int i = 0; i < 2; i++) {
            wchar_t *w = Py_DecodeLocale(paths[i], NULL);
            if (!w) { set_err(err, errlen, "could not decode path"); PyConfig_Clear(&config); return -3; }
            status = PyWideStringList_Append(&config.module_search_paths, w);
            PyMem_RawFree(w);
            if (PyStatus_Exception(status)) goto fail;
        }
    }

    status = Py_InitializeFromConfig(&config);
    if (PyStatus_Exception(status)) goto fail;
    PyConfig_Clear(&config);

    if (PyRun_SimpleString(bootstrap) != 0) {
        set_err(err, errlen, "bootstrap script failed");
        return -4;
    }

    PyObject *main_mod = PyImport_AddModule("__main__");
    PyObject *dict = main_mod ? PyModule_GetDict(main_mod) : NULL;
    g_run_fn = dict ? PyDict_GetItemString(dict, "_ide_run") : NULL;
    g_repl_fn = dict ? PyDict_GetItemString(dict, "_ide_repl") : NULL;
    if (!g_run_fn || !g_repl_fn) {
        set_err(err, errlen, "runner functions missing");
        return -5;
    }
    Py_INCREF(g_run_fn);
    Py_INCREF(g_repl_fn);

    PyEval_SaveThread();
    return 0;

fail:
    set_err(err, errlen, status.err_msg);
    PyConfig_Clear(&config);
    return -6;
}

void ide_py_run(const char *code, const char *name) {
    PyGILState_STATE st = PyGILState_Ensure();
    g_run_thread = PyThread_get_thread_ident();
    PyObject *r = PyObject_CallFunction(g_run_fn, "ss", code, name);
    if (!r) PyErr_Print(); else Py_DECREF(r);
    g_run_thread = 0;
    PyGILState_Release(st);
}

void ide_py_repl(const char *line) {
    PyGILState_STATE st = PyGILState_Ensure();
    g_run_thread = PyThread_get_thread_ident();
    PyObject *r = PyObject_CallFunction(g_repl_fn, "s", line);
    if (!r) PyErr_Print(); else Py_DECREF(r);
    g_run_thread = 0;
    PyGILState_Release(st);
}

void ide_py_interrupt(void) {
    unsigned long t = g_run_thread;
    if (!t) return;
    PyGILState_STATE st = PyGILState_Ensure();
    PyThreadState_SetAsyncExc(t, PyExc_KeyboardInterrupt);
    PyGILState_Release(st);
}
