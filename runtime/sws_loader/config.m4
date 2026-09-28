PHP_ARG_ENABLE([sws_loader],
  [whether to enable sws_loader],
  [AS_HELP_STRING([--enable-sws-loader], [Enable SWS protected source loader])],
  [no])

if test "$PHP_SWS_LOADER" != "no"; then
  PHP_ADD_LIBRARY([crypto], [1], [SWS_LOADER_SHARED_LIBADD])
  PHP_SUBST([SWS_LOADER_SHARED_LIBADD])
  PHP_NEW_EXTENSION([sws_loader], [sws_loader.c], [$ext_shared])
fi
