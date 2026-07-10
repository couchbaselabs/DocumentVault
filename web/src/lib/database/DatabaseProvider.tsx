import type { VaultDatabase } from './types';
import { createContext, useContext, type ReactNode } from 'react';

export interface DatabaseContext {
  db: VaultDatabase;
}

export const DatabaseContext = createContext<DatabaseContext | null>(null);

export function DatabaseProvider({
  db,
  children,
}: {
  db: VaultDatabase;
  children: ReactNode;
}) {
  return (
    <DatabaseContext.Provider value={{ db }}>
      {children}
    </DatabaseContext.Provider>
  );
}

export function useDatabase() {
  const context = useContext(DatabaseContext);
  if (!context) {
    throw new Error('useDatabase must be used within a DatabaseProvider!');
  }
  return context.db;
}
