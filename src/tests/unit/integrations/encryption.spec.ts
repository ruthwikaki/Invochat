
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createOrUpdateSecret, getSecret } from '@/features/integrations/services/encryption';

// Mock the Supabase admin client
const mockSupabaseVault = {
  secrets: {
    create: vi.fn(),
    retrieve: vi.fn(),
    update: vi.fn(),
  },
};
vi.mock('@/lib/supabase/admin', () => ({
  getServiceRoleClient: vi.fn(() => ({
    vault: mockSupabaseVault
  })),
}));

describe('Encryption Service (Supabase Vault)', () => {
  const companyId = 'company-id-123';
  const platform = 'shopify';
  const secretValue = 'shpat_test_secret_token';
  const secretName = `${platform}_token_${companyId}`;

  beforeEach(() => {
    vi.resetAllMocks();
  });

  describe('createOrUpdateSecret', () => {
    it('should create a new secret if it does not exist', async () => {
      mockSupabaseVault.secrets.create.mockResolvedValue({ data: { id: 'secret-id' }, error: null });

      await createOrUpdateSecret(companyId, platform, secretValue);

      expect(mockSupabaseVault.secrets.create).toHaveBeenCalledWith({
        name: secretName,
        secret: secretValue,
        description: `API token for ${platform} for company ${companyId}`,
      });
      expect(mockSupabaseVault.secrets.update).not.toHaveBeenCalled();
    });

    it('should update an existing secret if creation fails with a unique constraint error', async () => {
      // Simulate the unique constraint violation
      mockSupabaseVault.secrets.create.mockResolvedValue({
        data: null,
        error: { message: 'unique constraint' },
      });
      // Mock a successful update
      mockSupabaseVault.secrets.update.mockResolvedValue({ data: { id: 'updated-secret-id' }, error: null });

      await createOrUpdateSecret(companyId, platform, secretValue);

      expect(mockSupabaseVault.secrets.create).toHaveBeenCalledOnce();
      expect(mockSupabaseVault.secrets.update).toHaveBeenCalledWith(secretName, {
        secret: secretValue,
      });
    });

    it('should throw an error if creation fails for a reason other than uniqueness', async () => {
      mockSupabaseVault.secrets.create.mockResolvedValue({
        data: null,
        error: { message: 'Internal Server Error' },
      });

      await expect(createOrUpdateSecret(companyId, platform, secretValue)).rejects.toThrow('Failed to create secret: Internal Server Error');
    });
  });

  describe('getSecret', () => {
    it('should retrieve and return the decrypted secret value', async () => {
      mockSupabaseVault.secrets.retrieve.mockResolvedValue({
        data: { secret: secretValue },
        error: null,
      });

      const result = await getSecret(companyId, platform);

      expect(mockSupabaseVault.secrets.retrieve).toHaveBeenCalledWith(secretName);
      expect(result).toBe(secretValue);
    });

    it('should return null if the secret is not found (404 error)', async () => {
      mockSupabaseVault.secrets.retrieve.mockResolvedValue({
        data: null,
        error: { message: '404 Not Found' },
      });

      const result = await getSecret(companyId, platform);
      expect(result).toBeNull();
    });

    it('should throw an error for other retrieval failures', async () => {
      mockSupabaseVault.secrets.retrieve.mockResolvedValue({
        data: null,
        error: { message: 'Permission denied' },
      });

      await expect(getSecret(companyId, platform)).rejects.toThrow('Failed to retrieve secret: Permission denied');
    });
  });
});
