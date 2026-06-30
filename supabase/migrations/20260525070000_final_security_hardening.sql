-- Migration: Revoke public execution on dispatch functions and consolidate reviews/ratings/feedbacks triggers into profiles.
-- Created at: 2026-05-25

-- 1. Revoke PUBLIC and anon execution permissions from the dispatch functions:
REVOKE EXECUTE ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reject_ride(UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- Grants them to authenticated (drivers/riders) and service_role specifically:
GRANT EXECUTE ON FUNCTION public.assign_driver_to_ride(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reject_ride(UUID, TEXT) TO authenticated, service_role;

-- 2. Consolidate feedbacks, ratings, and reviews into profiles.
-- Create or replace function to calculate and update rating columns in profiles table.
CREATE OR REPLACE FUNCTION public.sync_profile_ratings()
RETURNS TRIGGER AS $$
DECLARE
  v_user_ids text[];
  v_user_id text;
BEGIN
  -- Determine affected user IDs based on the operations
  IF TG_OP = 'INSERT' THEN
    IF TG_TABLE_NAME = 'reviews' THEN
      v_user_ids := ARRAY[NEW.reviewed_id];
    ELSIF TG_TABLE_NAME = 'ratings' THEN
      v_user_ids := ARRAY[NEW.rated_user];
    ELSIF TG_TABLE_NAME = 'feedbacks' THEN
      v_user_ids := ARRAY[NEW.driver_id];
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF TG_TABLE_NAME = 'reviews' THEN
      v_user_ids := ARRAY[OLD.reviewed_id];
    ELSIF TG_TABLE_NAME = 'ratings' THEN
      v_user_ids := ARRAY[OLD.rated_user];
    ELSIF TG_TABLE_NAME = 'feedbacks' THEN
      v_user_ids := ARRAY[OLD.driver_id];
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF TG_TABLE_NAME = 'reviews' THEN
      IF NEW.reviewed_id IS DISTINCT FROM OLD.reviewed_id THEN
        v_user_ids := ARRAY[OLD.reviewed_id, NEW.reviewed_id];
      ELSE
        v_user_ids := ARRAY[NEW.reviewed_id];
      END IF;
    ELSIF TG_TABLE_NAME = 'ratings' THEN
      IF NEW.rated_user IS DISTINCT FROM OLD.rated_user THEN
        v_user_ids := ARRAY[OLD.rated_user, NEW.rated_user];
      ELSE
        v_user_ids := ARRAY[NEW.rated_user];
      END IF;
    ELSIF TG_TABLE_NAME = 'feedbacks' THEN
      IF NEW.driver_id IS DISTINCT FROM OLD.driver_id THEN
        v_user_ids := ARRAY[OLD.driver_id, NEW.driver_id];
      ELSE
        v_user_ids := ARRAY[NEW.driver_id];
      END IF;
    END IF;
  END IF;

  -- Filter out nulls
  SELECT ARRAY_AGG(x) INTO v_user_ids
  FROM UNNEST(v_user_ids) x
  WHERE x IS NOT NULL;

  -- Re-calculate ratings for all affected user IDs
  IF v_user_ids IS NOT NULL AND array_length(v_user_ids, 1) > 0 THEN
    FOREACH v_user_id IN ARRAY v_user_ids LOOP
      WITH all_evaluations AS (
        SELECT rating::numeric AS val FROM public.reviews WHERE reviewed_id = v_user_id AND rating IS NOT NULL
        UNION ALL
        SELECT score::numeric AS val FROM public.ratings WHERE rated_user = v_user_id AND score IS NOT NULL
        UNION ALL
        SELECT rating::numeric AS val FROM public.feedbacks WHERE driver_id = v_user_id AND rating IS NOT NULL
      ),
      stats AS (
        SELECT 
          COALESCE(COUNT(*), 0) AS total_count,
          COALESCE(AVG(val), 5.00) AS avg_val
        FROM all_evaluations
      )
      UPDATE public.profiles p
      SET 
        rating = ROUND(s.avg_val::numeric, 2),
        average_rating = ROUND(s.avg_val::numeric, 2),
        rating_count = s.total_count
      FROM stats s
      WHERE p.id = v_user_id;
    END LOOP;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop triggers if they already exist, to ensure idempotency
DROP TRIGGER IF EXISTS trg_sync_profile_ratings_reviews ON public.reviews;
DROP TRIGGER IF EXISTS trg_sync_profile_ratings_ratings ON public.ratings;
DROP TRIGGER IF EXISTS trg_sync_profile_ratings_feedbacks ON public.feedbacks;

-- Create triggers
CREATE TRIGGER trg_sync_profile_ratings_reviews
AFTER INSERT OR UPDATE OR DELETE ON public.reviews
FOR EACH ROW EXECUTE FUNCTION public.sync_profile_ratings();

CREATE TRIGGER trg_sync_profile_ratings_ratings
AFTER INSERT OR UPDATE OR DELETE ON public.ratings
FOR EACH ROW EXECUTE FUNCTION public.sync_profile_ratings();

CREATE TRIGGER trg_sync_profile_ratings_feedbacks
AFTER INSERT OR UPDATE OR DELETE ON public.feedbacks
FOR EACH ROW EXECUTE FUNCTION public.sync_profile_ratings();

-- 3. Run a one-time calculation to sync all existing user ratings across profiles
WITH combined_ratings AS (
  SELECT reviewed_id AS user_id, rating::numeric AS val FROM public.reviews WHERE reviewed_id IS NOT NULL AND rating IS NOT NULL
  UNION ALL
  SELECT rated_user AS user_id, score::numeric AS val FROM public.ratings WHERE rated_user IS NOT NULL AND score IS NOT NULL
  UNION ALL
  SELECT driver_id AS user_id, rating::numeric AS val FROM public.feedbacks WHERE driver_id IS NOT NULL AND rating IS NOT NULL
),
aggregated AS (
  SELECT 
    user_id,
    COUNT(*) AS total_count,
    ROUND(AVG(val), 2) AS avg_val
  FROM combined_ratings
  GROUP BY user_id
)
UPDATE public.profiles p
SET 
  rating = COALESCE(a.avg_val, 5.00),
  average_rating = COALESCE(a.avg_val, 5.00),
  rating_count = COALESCE(a.total_count, 0)
FROM (
  SELECT id FROM public.profiles
) p_list
LEFT JOIN aggregated a ON p_list.id = a.user_id
WHERE p.id = p_list.id;
