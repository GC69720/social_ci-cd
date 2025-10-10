from django.conf import settings

class SecurityHeadersMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        debug = getattr(settings, "DEBUG", False)

        if debug:
            csp = (
                "default-src 'self'; "
                "img-src 'self' data: blob:; "
                "font-src 'self' data:; "
                "connect-src 'self' http: https: ws: wss:; "
                "style-src 'self' 'unsafe-inline'; "
                "script-src 'self' 'unsafe-inline' 'unsafe-eval'"
            )
        else:
            csp = (
                "default-src 'self'; "
                "img-src 'self' data:; "
                "font-src 'self' data:; "
                "connect-src 'self'; "
                "style-src 'self'; "
                "script-src 'self'"
            )

        response["Content-Security-Policy"] = csp
        response["X-Content-Type-Options"] = "nosniff"
        response["Referrer-Policy"] = "no-referrer"
        response["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
        if not debug:
            response["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains; preload"
        return response
