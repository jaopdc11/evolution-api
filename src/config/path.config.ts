import { join } from 'path';

// vps: EVOLUTION_DADOS moves the writable data (sessions, store) out of the
// release directory. Unset, everything stays under the cwd, as upstream.
const DADOS = process.env.EVOLUTION_DADOS || process.cwd();

export const ROOT_DIR = process.cwd();
export const INSTANCE_DIR = join(DADOS, 'instances');
export const SRC_DIR = join(ROOT_DIR, 'src');
export const AUTH_DIR = join(DADOS, 'store', 'auth');
export const STORE_DIR = join(DADOS, 'store');
