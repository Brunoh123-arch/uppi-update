-- ==============================================================================
-- DATABASE ORGANIZER & CLEANUP MIGRATION
-- Remove old wallet_balance from profiles and migrate to new wallets table
-- ==============================================================================

-- 1. Sync any existing wallet_balance to the new wallets table
DO $$ 
BEGIN
  -- Insert missing wallets
  INSERT INTO public.wallets (user_id, balance)
  SELECT id, COALESCE(wallet_balance, 0)
  FROM public.profiles
  ON CONFLICT (user_id) DO NOTHING;

  -- Update existing wallets with profiles balance if wallets balance is 0 and profile is > 0
  UPDATE public.wallets w
  SET balance = p.wallet_balance,
      updated_at = now()
  FROM public.profiles p
  WHERE w.user_id = p.id
    AND w.balance = 0
    AND p.wallet_balance > 0;
EXCEPTION
  WHEN undefined_column THEN
    -- Column wallet_balance might already be dropped or not exist
    NULL;
END $$;

-- 2. Drop the old security trigger that blocked direct updates to wallet_balance
DROP TRIGGER IF EXISTS enforce_wallet_security ON public.profiles;

-- 3. Drop the associated trigger function
DROP FUNCTION IF EXISTS public.block_wallet_update();

-- 4. Safely drop the obsolete wallet_balance column from profiles
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'wallet_balance') THEN
    ALTER TABLE public.profiles DROP COLUMN wallet_balance;
  END IF;
END $$;
