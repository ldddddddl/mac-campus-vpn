package configs

import "testing"

func TestDefault(t *testing.T) {
	cfg := Default()
	if cfg.Protocol != "easyconnect" {
		t.Fatalf("Protocol = %q, want easyconnect", cfg.Protocol)
	}
	if cfg.ServerAddress != "" {
		t.Fatalf("ServerAddress = %q, want derived default", cfg.ServerAddress)
	}
	if cfg.ServerPort != 443 {
		t.Fatalf("ServerPort = %d, want 443", cfg.ServerPort)
	}
	if cfg.SocksBind != "127.0.0.1:11080" || cfg.HTTPBind != "" {
		t.Fatalf("proxy defaults = %q, %q; want 127.0.0.1:11080 and empty HTTPBind", cfg.SocksBind, cfg.HTTPBind)
	}
	if cfg.InsecureSkipVerify {
		t.Fatal("InsecureSkipVerify should default to false")
	}
}
