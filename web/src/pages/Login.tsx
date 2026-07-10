import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Shield, AlertCircle, Loader2, Eye, EyeOff, Info, User, Lock, ArrowRight } from "lucide-react";
import { initializeDatabase } from "@/lib/database/initDatabase";
import { syncOnce } from "@/lib/database/replicator";
import { storeCredentials, extractTenantIdFromEmail } from "@/lib/auth";
import { toast } from "sonner";

interface DemoCredential {
  email: string;
  password: string;
  role: string;
}

const DEMO_CREDENTIALS: DemoCredential[] = [
  {
    email: "guest@local.com",
    password: "password",
    role: "Local Sandbox (Guest)"
  },
  {
    email: "austin@acmecorp.com",
    password: "Password123!",
    role: "Corporate Tenant (Acme Admin)"
  }
];

const Login = () => {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [showDemoDialog, setShowDemoDialog] = useState(false);

  // Set background color matching DocumentVault
  useEffect(() => {
    const originalBackground = document.body.style.backgroundColor;
    document.body.style.backgroundColor = '#f1f5f9';

    return () => {
      document.body.style.backgroundColor = originalBackground;
    };
  }, []);

  const performLogin = async (loginEmail: string, loginPassword: string) => {
    setError("");
    setLoading(true);
    setShowDemoDialog(false);

    try {
      const tenantId = extractTenantIdFromEmail(loginEmail);
      console.log('📧 Extracted tenant ID:', tenantId);

      // Initialize database for this tenant
      console.log('💾 Initializing database...');
      const db = await initializeDatabase(tenantId);
      console.log('✅ Database initialized');

      // Sync once to verify sync connection
      console.log('🔄 Verifying sync connection...');
      try {
        await syncOnce(db, tenantId, loginEmail, loginPassword);
        toast.success("Sync connection verified!", {
          description: "Connected to Capella App Services.",
        });
      } catch (syncErr: any) {
        console.warn('⚠️ Sync verification failed (using local offline bypass):', syncErr.message);
        toast.warning("Local Offline Mode Enabled", {
          description: "Running in local database sandbox.",
        });
      }

      // Store credentials
      storeCredentials(loginEmail, loginPassword);
      console.log('✅ Credentials stored successfully');

      // Show success message
      toast.success("Login successful!", {
        description: `Welcome to DocumentVault Dashboard`,
      });

      // Redirect to dashboard
      window.location.href = '/dashboard';

    } catch (err: any) {
      console.error('❌ Login failed:', err);
      const errorMessage = err.message || 'Login failed. Please verify credentials.';
      setError(errorMessage);
      toast.error("Login failed", {
        description: errorMessage,
      });
    } finally {
      setLoading(false);
    }
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    await performLogin(email, password);
  };

  const handleDemoCredentialSelect = async (credential: DemoCredential) => {
    await performLogin(credential.email, credential.password);
  };

  return (
    <div className="min-h-screen flex flex-col items-center justify-between p-6 md:p-8" style={{ backgroundColor: '#f1f5f9' }}>
      <div className="flex-1 flex flex-col items-center justify-center w-full max-w-md space-y-8">
        {/* Header with Shield Icon */}
        <div className="text-center space-y-6">
          <div className="flex justify-center">
            <div className="w-24 h-24 bg-indigo-600 rounded-3xl flex items-center justify-center shadow-lg shadow-indigo-600/30">
              <Shield className="h-12 w-12 text-white" strokeWidth={2} />
            </div>
          </div>

          <div>
            <h1 className="text-3xl md:text-4xl font-bold text-slate-900 mb-2">
              DocumentVault
            </h1>
            <p className="text-base text-slate-500 font-medium">
              Enterprise Case File & Matter Manager
            </p>
          </div>
        </div>

        {/* Login Form */}
        <div className="w-full space-y-4">
          {error && (
            <div className="flex items-center gap-2 p-3 bg-red-50 border border-red-200 rounded-xl text-red-700 text-sm">
              <AlertCircle className="h-4 w-4 flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleLogin} className="space-y-4">
            {/* Username Field */}
            <div className="space-y-2">
              <label htmlFor="email" className="text-sm font-semibold text-slate-700">
                Email Address
              </label>
              <div className="relative">
                <div className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400">
                  <User className="h-5 w-5" />
                </div>
                <Input
                  id="email"
                  type="email"
                  placeholder="guest@local.com"
                  className="pl-11 h-12 bg-white border-slate-200 rounded-xl text-slate-900 placeholder:text-slate-400 focus:border-indigo-600 focus:ring-1 focus:ring-indigo-600"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  disabled={loading}
                />
              </div>
            </div>

            {/* Password Field */}
            <div className="space-y-2">
              <label htmlFor="password" className="text-sm font-semibold text-slate-700">
                Password
              </label>
              <div className="relative">
                <div className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400">
                  <Lock className="h-5 w-5" />
                </div>
                <Input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  placeholder="••••••••"
                  className="pl-11 pr-11 h-12 bg-white border-slate-200 rounded-xl text-slate-900 placeholder:text-slate-400 focus:border-indigo-600 focus:ring-1 focus:ring-indigo-600"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  disabled={loading}
                />
                <button
                  type="button"
                  className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                  onClick={() => setShowPassword(!showPassword)}
                  disabled={loading}
                >
                  {showPassword ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
                </button>
              </div>
            </div>

            <Button
              type="submit"
              className="w-full h-12 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl font-semibold shadow-md shadow-indigo-600/10 flex items-center justify-center gap-2"
              disabled={loading}
            >
              {loading ? (
                <>
                  <Loader2 className="h-5 w-5 animate-spin" />
                  <span>Connecting...</span>
                </>
              ) : (
                <>
                  <span>Access Vault</span>
                  <ArrowRight className="h-5 w-5" />
                </>
              )}
            </Button>
          </form>

          {/* Quick Demo Login Option */}
          <Dialog open={showDemoDialog} onOpenChange={setShowDemoDialog}>
            <DialogTrigger asChild>
              <Button
                variant="outline"
                className="w-full h-12 bg-white border-slate-200 hover:bg-slate-50 text-slate-700 rounded-xl font-medium flex items-center justify-center gap-2"
                disabled={loading}
              >
                <Info className="h-5 w-5" />
                <span>Show Demo Credentials</span>
              </Button>
            </DialogTrigger>
            <DialogContent className="bg-white border-slate-100 max-w-sm rounded-2xl p-6">
              <DialogHeader>
                <DialogTitle className="text-xl font-bold text-slate-900">Demo Profiles</DialogTitle>
                <DialogDescription className="text-slate-500">
                  Select a predefined profile to test real-time sync with DocumentVault.
                </DialogDescription>
              </DialogHeader>

              <div className="space-y-3 pt-4">
                {DEMO_CREDENTIALS.map((cred, idx) => (
                  <button
                    key={idx}
                    className="w-full text-left p-4 bg-slate-50 hover:bg-slate-100 border border-slate-200 rounded-xl transition-all flex flex-col space-y-1 focus:ring-2 focus:ring-indigo-600 focus:outline-none"
                    onClick={() => handleDemoCredentialSelect(cred)}
                  >
                    <span className="font-bold text-slate-900 text-sm">{cred.role}</span>
                    <span className="text-slate-500 text-xs font-mono">{cred.email}</span>
                  </button>
                ))}
              </div>
            </DialogContent>
          </Dialog>
        </div>
      </div>

      {/* Powered by Couchbase */}
      <div className="flex flex-col items-center gap-2 pt-8">
        <div className="flex items-center gap-2">
          <img
            src="/images/couchbase-logo.png"
            alt="Couchbase"
            className="h-5 w-auto object-contain brightness-95"
            onError={(e) => {
              (e.target as HTMLElement).style.display = 'none';
            }}
          />
          <span className="text-xs font-bold tracking-wide uppercase text-slate-400">
            Powered by Couchbase Lite
          </span>
        </div>
      </div>
    </div>
  );
};

export default Login;