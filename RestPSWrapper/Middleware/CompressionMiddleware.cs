using System.IO.Compression;

namespace RestPSWrapper.Middleware;

public class CompressionMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<CompressionMiddleware> _logger;

    public CompressionMiddleware(RequestDelegate next, ILogger<CompressionMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var originalBodyStream = context.Response.Body;

        using (var memoryStream = new MemoryStream())
        {
            context.Response.Body = memoryStream;

            await _next(context);

            if (context.Response.StatusCode == 200 &&
                (context.Request.Path.StartsWithSegments("/api") ||
                 context.Request.Path.Value?.EndsWith(".js") == true ||
                 context.Request.Path.Value?.EndsWith(".css") == true))
            {
                context.Response.Headers["Content-Encoding"] = "gzip";

                using (var gzipStream = new GZipStream(originalBodyStream, CompressionMode.Compress))
                {
                    memoryStream.Seek(0, SeekOrigin.Begin);
                    await memoryStream.CopyToAsync(gzipStream);
                }
            }
            else
            {
                memoryStream.Seek(0, SeekOrigin.Begin);
                await memoryStream.CopyToAsync(originalBodyStream);
            }
        }
    }
}
