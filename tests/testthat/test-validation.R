context("validation")


test_that("find schema root", {
  expect_equal(schema_root("."), normalizePath("."))
  expect_error(schema_root(tempfile()))
})


test_that("default validation", {
  withr::with_envvar(c("PORCELAIN_VALIDATE" = NA_character_), {
    expect_true(porcelain_validate_default(TRUE))
    expect_false(porcelain_validate_default(FALSE))
    expect_false(porcelain_validate_default(NULL))
  })

  withr::with_envvar(c("PORCELAIN_VALIDATE" = "true"), {
    expect_true(porcelain_validate_default(TRUE))
    expect_false(porcelain_validate_default(FALSE))
    expect_true(porcelain_validate_default(NULL))
  })

  withr::with_envvar(c("PORCELAIN_VALIDATE" = "false"), {
    expect_true(porcelain_validate_default(TRUE))
    expect_false(porcelain_validate_default(FALSE))
    expect_false(porcelain_validate_default(NULL))
  })
})


test_that("validate successful return", {
  path <- system_file("schema/response-success.schema.json",
                      package = "porcelain")
  v <- jsonvalidate::json_validator(path, "ajv")
  expect_true(v(to_json(response_success(NULL))))
  expect_true(v(to_json(response_success(1))))
})


test_that("validate errors", {
  path <- system_file("schema/response-failure.schema.json",
                      package = "porcelain")
  v <- jsonvalidate::json_validator(path, "ajv")

  f <- function(x) {
    porcelain_process_error(porcelain_error_object(x, 400L))
  }

  e1 <- f(list("ERROR" = list(detail = "reason")))
  expect_equal(e1$value$errors, list(list(error = jsonlite::unbox("ERROR"),
                                          detail = jsonlite::unbox("reason"))))
  expect_true(v(e1$body))

  e2 <- f(list("ERROR" = NULL))
  expect_equal(e2$value$errors, list(list(error = jsonlite::unbox("ERROR"),
                                          detail = NULL)))
  expect_true(v(e2$body))

  e3 <- f(list("ERROR" = NULL, "OTHER" = list(detail = "reason")))
  expect_equal(e3$value$errors,
               list(list(error = jsonlite::unbox("ERROR"),
                         detail = NULL),
                    list(error = jsonlite::unbox("OTHER"),
                         detail = jsonlite::unbox("reason"))))
  expect_true(v(e3$body))

  e4 <- f(list("ERROR" = NULL, "OTHER" = list(detail = "reason")))
  expect_equal(e4$value$errors,
               list(list(error = jsonlite::unbox("ERROR"),
                         detail = NULL),
                    list(error = jsonlite::unbox("OTHER"),
                         detail = jsonlite::unbox("reason"))))
  expect_true(v(e4$body))

  e5 <- f(list("ERROR" = list(detail = "reason",
                              key = jsonlite::unbox("key"),
                              trace = c(jsonlite::unbox("the"),
                                        jsonlite::unbox("trace")))))
  expect_equal(e5$value$errors,
               list(list(error = jsonlite::unbox("ERROR"),
                         detail = jsonlite::unbox("reason"),
                         key = jsonlite::unbox("key"),
                         trace = c(jsonlite::unbox("the"),
                                   jsonlite::unbox("trace")))))
  expect_true(v(e5$body))
})


test_that("validate schema - success", {
  hello <- function() {
    jsonlite::unbox("hello")
  }
  endpoint <- porcelain_endpoint$new(
    "GET", "/", hello,
    returning = porcelain_returning_json("String", "schema"),
    validate = TRUE)
  res <- endpoint$run()
  expect_equal(res$status_code, 200L)
})


test_that("validate schema", {
  hello <- function() {
    jsonlite::unbox(1)
  }
  endpoint <- porcelain_endpoint$new(
    "GET", "/", hello,
    returning = porcelain_returning_json("String", "schema"),
    validate = TRUE)
  res <- endpoint$run()

  expect_is(res, "porcelain_response")
  expect_equal(res$status_code, 500L)
  expect_equal(res$content_type, "application/json")
  expect_equal(res$body, to_json_string(res$value))
  expect_is(res$error, "porcelain_validation_error")

  expect_equal(to_json_string(response_success(hello())), res$error$json)
})


test_that("can skip validation", {
  hello <- function() {
    jsonlite::unbox(1)
  }
  endpoint <- porcelain_endpoint$new(
    "GET", "/", hello,
    returning = porcelain_returning_json("String", "schema"),
    validate = FALSE)
  res <- endpoint$run()
  expect_equal(res$status_code, 200L)
})


test_that("validation respects default", {
  f <- function() {
    porcelain_endpoint$new(
      "GET", "/", function() jsonlite::unbox(1),
      returning = porcelain_returning_json(
        "String", "schema"))$run()$status_code
  }

  withr::with_envvar(c("PORCELAIN_VALIDATE" = NA_character_),
                     expect_equal(f(), 200))
  withr::with_envvar(c("PORCELAIN_VALIDATE" = "false"),
                     expect_equal(f(), 200))
  withr::with_envvar(c("PORCELAIN_VALIDATE" = "true"),
                     expect_equal(f(), 500))
})


test_that("override validation defaults at the api level", {
  endpoint <- porcelain_endpoint$new(
    "GET", "/", function() jsonlite::unbox(1),
    returning = porcelain_returning_json("String", "schema"),
    validate = TRUE)
  api <- porcelain$new(validate = FALSE)
  api$handle(endpoint)
  expect_true(endpoint$validate)

  expect_equal(endpoint$run()$status_code, 500)
  expect_equal(api$request("GET", "/")$status, 200)
})


test_that("allow missing schema", {
  hello <- function() {
    jsonlite::unbox(1)
  }
  endpoint <- porcelain_endpoint$new(
    "GET", "/", hello,
    returning = porcelain_returning_json(),
    validate = TRUE)
  res <- endpoint$run()
  expect_equal(res$status_code, 200L)
  expect_equal(res$content_type, "application/json")
  expect_equal(res$data, hello())
  expect_equal(res$body, to_json_string(response_success(res$data)))
})


test_that("validate binary output", {
  binary <- function() {
    "not binary"
  }
  endpoint <- porcelain_endpoint$new(
    "GET", "/binary", binary,
    returning = porcelain_returning_binary(),
    validate = TRUE)
  res <- endpoint$run()
  expect_equal(res$status_code, 500L)
  endpoint$validate <- FALSE
  res <- endpoint$run()
  expect_equal(res$status_code, 200L)
})
