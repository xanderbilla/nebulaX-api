package com.example.demo.exception;

/**
 * Exception thrown when video processing operations fail.
 * This covers various processing errors including validation failures,
 * encoding issues, metadata extraction problems, and file system errors.
 * 
 * @author Xander Billa
 * @since August 3, 2025
 * @see com.example.demo.service.VideoService
 * @see com.example.demo.handler.GlobalExceptionHandler
 */
public class VideoProcessingException extends RuntimeException {
    public VideoProcessingException(String message) {
        super(message);
    }

    public VideoProcessingException(String message, Throwable cause) {
        super(message, cause);
    }
}
