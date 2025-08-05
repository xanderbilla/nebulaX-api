package com.example.demo.exception;

/**
 * Exception thrown when S3 operations fail during video processing.
 * This includes upload failures, download errors, permission issues,
 * and S3 service connectivity problems.
 * 
 * @author Xander Billa
 * @since August 5, 2025
 * @see com.example.demo.service.VideoService
 * @see com.example.demo.handler.GlobalExceptionHandler
 */
public class S3OperationException extends RuntimeException {
    public S3OperationException(String message) {
        super(message);
    }

    public S3OperationException(String message, Throwable cause) {
        super(message, cause);
    }
}
