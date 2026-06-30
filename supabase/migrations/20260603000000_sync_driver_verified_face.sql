-- Migration: Sincronizar foto de perfil do motorista com a selfie da verificação facial aprovada
-- Data: 2026-06-03

CREATE OR REPLACE FUNCTION public.sync_driver_verified_face_to_profile()
RETURNS TRIGGER AS $$
BEGIN
    -- Se a verificação facial foi aprovada (automaticamente ou manualmente pelo admin)
    -- e existe uma selfie válida, atualiza o avatar_url do perfil do motorista.
    IF NEW.status IN ('approved', 'auto_approved') AND NEW.selfie_url IS NOT NULL THEN
        UPDATE public.profiles_raw
        SET avatar_url = NEW.selfie_url
        WHERE id = NEW.driver_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger disparado após inserção ou atualização de status na verificação facial
DROP TRIGGER IF EXISTS trg_sync_driver_verified_face_to_profile ON public.driver_face_verifications;
CREATE TRIGGER trg_sync_driver_verified_face_to_profile
AFTER INSERT OR UPDATE OF status ON public.driver_face_verifications
FOR EACH ROW
EXECUTE FUNCTION public.sync_driver_verified_face_to_profile();
