g_declare_cafs main
g_declare_main main

g_globstart gm$print, 2
g_eval
g_print
g_cons 0, 0
g_updcons 0, 2, 1
g_return

g_globstart id, 1
g_update 1
g_unwind

g_globstart main, 0
g_pushint 0
g_pushglobal id, 1
g_mkap 1
g_pushglobal gm$print, 2
g_updap 1, 1
g_unwind
