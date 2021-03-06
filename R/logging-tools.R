#' Log user activity
#'
#' @description These functions connects to database and log specific user activity. See more in \strong{Details} section.
#'
#' @details \code{log_input} and \code{log_button} observe selected input value and registers its insertion or change inside specified database.
#' @param user_connection_data List with user session and DB connection. See \link{initialize_connection}.
#' @param input input object inherited from server function.
#' @param input_id id of registered input control.
#' @param matching_values An object specified possible values to register.
#' @param input_type 'text' to registered bare input value, 'json' to parse value from JSON format.
#' @export
log_input <- function(user_connection_data, input, input_id,
                      matching_values = NULL, input_type = "text") {
  shiny::observeEvent(input[[input_id]], {
    input_value <- input[[input_id]]
    if (is.logical(input_value)) {
      input_value <- as.character(input_value)
    }
    if (!is.null(input_value)) {
      n_values <- length(input_value)
      if (!is.null(matching_values) && input_type == "json") {
        input_value <- parse_val(input_value)
      }
      if (is.null(matching_values) | (!is.null(matching_values) && input_value %in% matching_values)) {
        db <- user_connection_data$db_connection
        persist_log <- function(input_value, input_id) {
          res <- odbc::dbSendQuery(conn = db,
            DBI::sqlInterpolate(conn = db,
              "INSERT INTO user_log
              VALUES (?time, ?session, ?username, ?action, ?id, ?value)",
              time = as.character(Sys.time()), session = user_connection_data$session_id,
              username = user_connection_data$username,
              action = "input", id = input_id, value = input_value))
          odbc::dbClearResult(res)
        }
        if (n_values > 1) {
          input_ids <- sprintf("%s_%s", input_id, 1:n_values)
          purrr::walk2(input_value, input_ids, persist_log)
        } else {
          persist_log(input_value, input_id)
        }
      }
    }
  },
  priority = -1,
  ignoreInit = TRUE)
}

#' @rdname log_input
#' @export
log_button <- function(user_connection_data, input, button_id) {
  shiny::observeEvent(input[[button_id]], {
    db <- user_connection_data$db_connection
    res <- odbc::dbSendQuery(conn = db,
      DBI::sqlInterpolate(conn = db,
        "INSERT INTO user_log(time, session, username, action, id)
        VALUES (?time, ?session, ?username, ?action, ?id)",
        time = as.character(Sys.time()), session = user_connection_data$session_id,
        username = user_connection_data$username, action = "click", id = button_id))
    odbc::dbClearResult(res)
    },
    priority = -1,
    ignoreInit = TRUE
  )
}

#' @details Each function (except \code{log_custom_action}) store logs inside 'user_log' table.
#' It is required to build admin panel (See \link{initialize_admin_panel}).
#' @param table_name Specific table name to create or connect inside 'path_to_db'.
#' @param values Named list. Names of the list specify column names of \code{table_name} and list elements
#' corresponding values that should be intsert into the table. Column 'time' is filled automatically so
#' you cannot pass it on you own.
#' @rdname log_input
#' @export
log_custom_action <- function(user_connection_data, table_name = "user_log", values) {

  if (!all(names(user_connection_data) == c("username", "session_id", "db_connection"))) {
    stop("user_connection_data should be list of session_id and db_connection objects!")
  }

  if ("time" %in% names(values)) {
    stop("You mustn't pass 'time' value into database. It is set automatically.")
  }

  send_query_df <- as.data.frame(c(time = as.character(Sys.time()), values), stringsAsFactors = FALSE)

  db <- user_connection_data$db_connection

  odbc::dbWriteTable(db, table_name, send_query_df, overwrite = FALSE, append = TRUE, row.names = FALSE)

}

#' @rdname log_input
#' @param action Specified action value that should be added to 'user_log' table.
#' @export
log_action <- function(user_connection_data, action) {
  log_custom_action(user_connection_data, "user_log", values = list(
    "session" = user_connection_data$session_id, "username" = user_connection_data$username, "action" = action)
  )
}

#' @rdname log_input
#' @param id Id of clicked button.
#' @export
log_click <- function(user_connection_data, id) {
  log_custom_action(user_connection_data, "user_log", values = list(
    "session" = user_connection_data$session_id, "username" = user_connection_data$username,
    "action" = "click", "id" = id)
  )
}

#' @rdname log_input
#' @export
log_login <- function(user_connection_data) {
  log_custom_action(user_connection_data, "user_log", values = list(
    "session" = user_connection_data$session_id, "username" = user_connection_data$username, "action" = "login")
  )
}

#' @details \code{log_logout} should be used inside \code{observe} function. It is based on \code{shiny::onStop}.
#' @rdname log_input
#' @export
log_logout <- function(user_connection_data) {
  shiny::onStop(function() {
    log_custom_action(user_connection_data, "user_log", values = list(
      "session" = user_connection_data$session_id, "username" = user_connection_data$username, "action" = "logout")
    )
    odbc::dbDisconnect(user_connection_data$db_connection)
  })
}

#' @rdname log_input
#' @param detail Information that should describe session.
#' @export
log_session_detail <- function(user_connection_data, detail) {
  log_custom_action(user_connection_data, "session_details", values = list(
    "session" = user_connection_data$session_id, "detail" = detail)
  )
}

#' Browser info
#'
#' @description It sends info about user's browser to server.
#' Place it inside head tag of your Shiny app. You can get this value on server from \code{input[["browser_version"]]}.
#' You can also use log_browser_version function to log browser version into sqlite file.
#'
#' @examples
#' ## Only run examples in interactive R sessions
#' if (interactive()) {
#' library(shiny)
#' library(shiny.semantic)
#' library(shiny.admin)
#'
#' ui <- function() {
#'   shinyUI(
#'     semanticPage(
#'       tags$head(shiny.admin::browser_info_js),
#'       title = "Browser info example",
#'       textOutput("browser")
#'     )
#'   )
#' }
#'
#' server <- shinyServer(function(input, output) {
#'   output$browser <- renderText(input[["browser_version"]])
#' })
#'
#' shinyApp(ui = ui(), server = server)
#'}
#' @export
browser_info_js <- shiny::HTML("
    <script type='text/javascript'>
      $(document).on('shiny:sessioninitialized', function(event) {
        var br_ver = (function(){
          var ua= navigator.userAgent, tem,
          M= ua.match(/(opera|chrome|safari|firefox|msie|trident(?=\\/))\\/?\\s*(\\d+)/i) || [];
          if(/trident/i.test(M[1])){
            tem=  /\\brv[ :]+(\\d+)/g.exec(ua) || [];
            return 'IE '+(tem[1] || '');
          }
          if(M[1]=== 'Chrome'){
            tem= ua.match(/\\b(OPR|Edge)\\/(\\d+)/);
            if(tem!= null) return tem.slice(1).join(' ').replace('OPR', 'Opera');
          }
          M= M[2]? [M[1], M[2]]: [navigator.appName, navigator.appVersion, '-?'];
          if((tem= ua.match(/version\\/(\\d+)/i))!= null) M.splice(1, 1, tem[1]);
          return M.join(' ');
        })();

        Shiny.onInputChange(\"browser_version\", br_ver);}
      );
    </script>"
)


#' @rdname browser_info_js
#' @export
log_browser_version <- function(input, user_connection_data) {
  browser <- input$browser_version
  shiny::validate(shiny::need(browser, "'browser_info_js' should be set in app head"))
  log_custom_action(
    user_connection_data,
    table_name = "user_log",
    values = list(
      "session" = user_connection_data$session_id, "username" = user_connection_data$username,
      "action" = "browser", "value" = browser
    )
  )
}
