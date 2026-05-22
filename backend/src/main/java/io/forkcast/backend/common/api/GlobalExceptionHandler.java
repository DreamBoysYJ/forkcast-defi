package io.forkcast.backend.common.api;


import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

  @ExceptionHandler(MethodArgumentNotValidException.class)
  public ResponseEntity<ApiErrorResponse> handleValidationException(MethodArgumentNotValidException e) {
    String message = e.getBindingResult().getFieldErrors().stream().findFirst().map(fieldError ->
      fieldError.getField() + "must not be blank").orElse("Invalid request body");

    return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(ApiErrorResponse.of("INVALID_REQUEST", message));
  }

  @ExceptionHandler(DataIntegrityViolationException.class)
  public ResponseEntity<ApiErrorResponse> handleDataIntegrityViolation(DataIntegrityViolationException e) {
    return ResponseEntity.status(HttpStatus.CONFLICT)
      .body(ApiErrorResponse.of("DUPLICATE_TX_HASH", "이미 존재하는 트랜잭션입니다."));
  }

  @ExceptionHandler(IllegalArgumentException.class)
  public ResponseEntity<ApiErrorResponse> handleIllegalArgumentException(IllegalArgumentException e) {
    HttpStatus status = e.getMessage() != null && e.getMessage().startsWith("Pending tx already exists:")
      ? HttpStatus.CONFLICT : HttpStatus.BAD_REQUEST;

    String code = status == HttpStatus.CONFLICT ? "DUPLICATE_TX_HASH" : "BAD_REQUEST";

    return ResponseEntity.status(status).body(ApiErrorResponse.of(code, e.getMessage()));
  }

  @ExceptionHandler(Exception.class)
  public ResponseEntity<ApiErrorResponse> handleExecption(Exception e) {
    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(ApiErrorResponse.of("INTERNAL_ERROR",
      "Unexpected server error"));
  }
}
