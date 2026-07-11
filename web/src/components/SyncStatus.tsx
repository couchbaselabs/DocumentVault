import { useState, useEffect } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { 
  Cloud, 
  CloudOff, 
  RefreshCw, 
  WifiOff,
  CheckCircle2,
  AlertCircle 
} from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";

type SyncState = 'idle' | 'syncing' | 'offline' | 'error';

export function SyncStatus() {
  const [isOnline, setIsOnline] = useState(navigator.onLine);
  const [syncState, setSyncState] = useState<SyncState>('idle');
  const [lastSyncTime, setLastSyncTime] = useState<Date | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
      setSyncState('idle');
    };
    
    const handleOffline = () => {
      setIsOnline(false);
      setSyncState('offline');
    };

    const handleSyncStatus = (e: Event) => {
      const status = (e as CustomEvent).detail;
      const act = (status.status || status.activity || "").toLowerCase();
      if (act === 'connecting' || act === 'syncing') {
        setSyncState('syncing');
      } else {
        setSyncState('idle');
        setLastSyncTime(new Date());
        setErrorMsg(null);
      }
    };

    const handleSyncError = (e: Event) => {
      const error = (e as CustomEvent).detail;
      setSyncState('error');
      setErrorMsg(error.message || String(error));
    };

    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);
    window.addEventListener('cbl-sync-status', handleSyncStatus);
    window.addEventListener('cbl-sync-error', handleSyncError);

    return () => {
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
      window.removeEventListener('cbl-sync-status', handleSyncStatus);
      window.removeEventListener('cbl-sync-error', handleSyncError);
    };
  }, []);

  const getStatusConfig = () => {
    switch (syncState) {
      case 'syncing':
        return {
          icon: <RefreshCw className="h-3 w-3 animate-spin" />,
          label: 'Syncing',
          variant: 'secondary' as const,
          color: 'text-blue-600',
        };
      case 'offline':
        return {
          icon: isOnline ? <CloudOff className="h-3 w-3" /> : <WifiOff className="h-3 w-3" />,
          label: isOnline ? 'Offline Mode' : 'No Connection',
          variant: 'secondary' as const,
          color: 'text-gray-600',
        };
      case 'error':
        return {
          icon: <AlertCircle className="h-3 w-3" />,
          label: 'Sync Error',
          variant: 'destructive' as const,
          color: 'text-red-600',
        };
      default:
        return {
          icon: <Cloud className="h-3 w-3" />,
          label: 'Synced',
          variant: 'secondary' as const,
          color: 'text-muted-foreground',
        };
    }
  };

  const config = getStatusConfig();

  const getTooltipContent = () => {
    if (!isOnline) {
      return "You're offline. Changes will sync when you're back online.";
    }
    if (syncState === 'error') {
      return errorMsg || "Sync error occurred. Check console for details.";
    }
    if (lastSyncTime) {
      return `Last synced: ${lastSyncTime.toLocaleTimeString()}`;
    }
    return "Connected to Couchbase Capella";
  };

  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <div className="inline-flex cursor-help">
            <Badge 
              variant={config.variant} 
              className={`gap-2 ${config.color}`}
            >
              {config.icon}
              <span className="hidden sm:inline">{config.label}</span>
            </Badge>
          </div>
        </TooltipTrigger>
        <TooltipContent>
          <p>{getTooltipContent()}</p>
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}

// Optional: Detailed sync status component with more info
export function SyncStatusDetailed() {
  const [isOnline, setIsOnline] = useState(navigator.onLine);
  const [stats, setStats] = useState({
    docsInQueue: 0,
    docsSynced: 0,
    lastSync: null as Date | null,
  });

  useEffect(() => {
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);

    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);

    return () => {
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
    };
  }, []);

  return (
    <div className="flex flex-col gap-2 p-4 border rounded-lg bg-card">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Sync Status</h3>
        <SyncStatus />
      </div>
      
      <div className="space-y-1 text-xs text-muted-foreground">
        <div className="flex justify-between">
          <span>Connection:</span>
          <span className={isOnline ? "text-green-600" : "text-red-600"}>
            {isOnline ? "Online" : "Offline"}
          </span>
        </div>
        
        {stats.lastSync && (
          <div className="flex justify-between">
            <span>Last Sync:</span>
            <span>{stats.lastSync.toLocaleTimeString()}</span>
          </div>
        )}
        
        <div className="flex justify-between">
          <span>Documents Synced:</span>
          <span>{stats.docsSynced}</span>
        </div>
        
        {stats.docsInQueue > 0 && (
          <div className="flex justify-between">
            <span>Pending:</span>
            <span className="text-yellow-600">{stats.docsInQueue}</span>
          </div>
        )}
      </div>
    </div>
  );
}

