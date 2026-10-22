package handler

import (
	"errors"
	"log"
	"net"
	"net/http"
	"net/http/httptrace"
	"sync/atomic"
	"time"
)

// 仅记录请求阶段，不记录 URL、代理地址、授权码、请求头或响应体。
func traceGitHubTokenRequest(req *http.Request) (*http.Request, func(error, time.Duration)) {
	var phase atomic.Value
	phase.Store("request")
	trace := &httptrace.ClientTrace{
		DNSStart:          func(httptrace.DNSStartInfo) { phase.Store("dns") },
		ConnectStart:      func(string, string) { phase.Store("connect") },
		TLSHandshakeStart: func() { phase.Store("tls") },
		GotConn:           func(httptrace.GotConnInfo) { phase.Store("write_request") },
		WroteRequest: func(info httptrace.WroteRequestInfo) {
			if info.Err == nil {
				phase.Store("response_headers")
			}
		},
		GotFirstResponseByte: func() { phase.Store("response_body") },
	}
	return req.WithContext(httptrace.WithClientTrace(req.Context(), trace)), func(err error, elapsed time.Duration) {
		var networkError net.Error
		timedOut := errors.As(err, &networkError) && networkError.Timeout()
		log.Printf("github oauth provider session=%v stage=token network_error=true network_phase=%s timeout=%t duration_ms=%d",
			req.Context().Value(oauthRequestSessionKey{}), phase.Load(), timedOut, elapsed.Milliseconds())
	}
}
