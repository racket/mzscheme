(lambda (request failure)
  (case request
    [(name) "compile-plt"]
    [else (failure)]))
