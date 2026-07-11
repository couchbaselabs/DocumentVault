/**
 * Authentication and credentials management for DocumentVault
 */

export interface AuthCredentials {
  email: string;
  password: string;
  tenantId: string;
}

const AUTH_STORAGE_KEY = 'documentvault_auth_credentials';

/**
 * Extract Tenant ID from email domain
 * e.g., "admin@acme-corp.com" → "acme-corp", "guest@local.com" → "local"
 */
export function extractTenantIdFromEmail(email: string): string {
  const clean = email.trim().toLowerCase();
  const parts = clean.split('@');
  if (parts.length !== 2) return 'local';
  
  const domain = parts[1];
  const publicDomains = new Set([
    'gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com', 'icloud.com', 'me.com'
  ]);
  
  if (publicDomains.has(domain) || domain === 'local.com') {
    return 'local';
  }
  
  return domain.split('.')[0];
}

export function getAppServicesUrl(tenantId: string): string {
  const envUrl = import.meta.env.VITE_APP_SERVICES_URL;
  if (envUrl) {
    // Connect directly to Capella (requires CORS configuration on Capella)
    return `${envUrl}/docvault-${tenantId}`;
  }
  
  // Fallback to local proxy
  const isSecure = window.location.protocol === 'https:';
  const wsProtocol = isSecure ? 'wss:' : 'ws:';
  const host = window.location.host || 'localhost:8080';
  
  return `${wsProtocol}//${host}/sync-gateway/docvault-${tenantId}`;
}

/**
 * Store credentials securely in sessionStorage
 */
export function storeCredentials(email: string, password: string): void {
  const tenantId = extractTenantIdFromEmail(email);
  const credentials: AuthCredentials = {
    email,
    password,
    tenantId,
  };
  sessionStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(credentials));
}

/**
 * Retrieve stored credentials
 */
export function getStoredCredentials(): AuthCredentials | null {
  const stored = sessionStorage.getItem(AUTH_STORAGE_KEY);
  if (!stored) return null;

  try {
    return JSON.parse(stored) as AuthCredentials;
  } catch {
    return null;
  }
}

/**
 * Clear stored credentials (logout)
 */
export function clearCredentials(): void {
  sessionStorage.removeItem(AUTH_STORAGE_KEY);
}

/**
 * Check if user is authenticated
 */
export function isAuthenticated(): boolean {
  return getStoredCredentials() !== null;
}
