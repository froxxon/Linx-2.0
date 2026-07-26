using Microsoft.Extensions.Options;
using RestPSWrapper.Configuration;

namespace RestPSWrapper.Middleware;

/// <summary>
/// Middleware to enforce request body size limits
/// Prevents large payload attacks and resource exhaustion
/// </summary>
public class RequestSizeLimitMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestSizeLimitMiddleware> _logger;
    private readonly long _maxRequestBodySize;

    public RequestSizeLimitMiddleware(
        RequestDelegate next,
        ILogger<RequestSizeLimitMiddleware> logger,
        IOptions<ScriptVariablesConfig> options)
    {
        _next = next;
        _logger = logger;
        _maxRequestBodySize = options.Value.MaxRequestBodySizeBytes;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Only check for requests with body (POST, PUT, PATCH)
        if ((context.Request.Method == "POST" || context.Request.Method == "PUT" || context.Request.Method == "PATCH") &&
            _maxRequestBodySize > 0)
        {
            // Early check: if Content-Length is declared and already exceeds limit, reject immediately
            if (context.Request.ContentLength.HasValue && context.Request.ContentLength > _maxRequestBodySize)
            {
                await RejectRequest(context, context.Request.ContentLength.Value);
                return;
            }

            // For all requests (including chunked without Content-Length), wrap the body stream
            // to enforce size limit at read time
            var originalBody = context.Request.Body;
            var limitedStream = new SizeLimitedStream(
                originalBody,
                _maxRequestBodySize,
                () => RejectRequestDuringRead(context));

            context.Request.Body = limitedStream;

            try
            {
                await _next(context);
            }
            finally
            {
                // Restore original stream
                context.Request.Body = originalBody;
            }
        }
        else
        {
            await _next(context);
        }
    }

    private async Task RejectRequest(HttpContext context, long actualSize)
    {
        var requestId = context.Items["RequestId"]?.ToString() ?? "Unknown";
        _logger.LogWarning(
            "Request rejected - body size {ContentLength} exceeds limit {MaxSize}. RequestId: {RequestId}, Path: {Path}",
            actualSize, _maxRequestBodySize, requestId, context.Request.Path);

        context.Response.StatusCode = StatusCodes.Status413PayloadTooLarge;
        context.Response.ContentType = "application/json";
        await context.Response.WriteAsJsonAsync(new
        {
            error = "Payload Too Large",
            maxSize = _maxRequestBodySize,
            requestId = requestId
        });
    }

    private void RejectRequestDuringRead(HttpContext context)
    {
        var requestId = context.Items["RequestId"]?.ToString() ?? "Unknown";
        _logger.LogWarning(
            "Request rejected during read - body size exceeds limit {MaxSize}. RequestId: {RequestId}, Path: {Path}",
            _maxRequestBodySize, requestId, context.Request.Path);
    }
}

/// <summary>
/// Stream wrapper that enforces a maximum read size limit
/// Throws when the limit is exceeded
/// </summary>
internal class SizeLimitedStream : Stream
{
    private readonly Stream _innerStream;
    private readonly long _maxSize;
    private readonly Action _onLimitExceeded;
    private long _totalBytesRead;

    public SizeLimitedStream(Stream innerStream, long maxSize, Action onLimitExceeded)
    {
        _innerStream = innerStream;
        _maxSize = maxSize;
        _onLimitExceeded = onLimitExceeded;
        _totalBytesRead = 0;
    }

    public override bool CanRead => _innerStream.CanRead;
    public override bool CanSeek => _innerStream.CanSeek;
    public override bool CanWrite => _innerStream.CanWrite;
    public override long Length => _innerStream.Length;
    public override long Position
    {
        get => _innerStream.Position;
        set => _innerStream.Position = value;
    }

    public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        var bytesRead = await _innerStream.ReadAsync(buffer, offset, count, cancellationToken);
        _totalBytesRead += bytesRead;

        if (_totalBytesRead > _maxSize)
        {
            _onLimitExceeded();
            throw new InvalidOperationException($"Request body size exceeds the maximum allowed size of {_maxSize} bytes.");
        }

        return bytesRead;
    }

    public override int Read(byte[] buffer, int offset, int count)
    {
        var bytesRead = _innerStream.Read(buffer, offset, count);
        _totalBytesRead += bytesRead;

        if (_totalBytesRead > _maxSize)
        {
            _onLimitExceeded();
            throw new InvalidOperationException($"Request body size exceeds the maximum allowed size of {_maxSize} bytes.");
        }

        return bytesRead;
    }

    public override void Flush() => _innerStream.Flush();
    public override Task FlushAsync(CancellationToken cancellationToken) => _innerStream.FlushAsync(cancellationToken);
    public override long Seek(long offset, SeekOrigin origin) => _innerStream.Seek(offset, origin);
    public override void SetLength(long value) => _innerStream.SetLength(value);
    public override void Write(byte[] buffer, int offset, int count) => _innerStream.Write(buffer, offset, count);

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            // Don't dispose the inner stream - it's owned by the HttpContext
        }
        base.Dispose(disposing);
    }
}