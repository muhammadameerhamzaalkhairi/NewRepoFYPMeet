-- Run this file in the Supabase SQL Editor before using Restart.
-- Matches the existing RPCs: SECURITY INVOKER, authenticated users only.
CREATE OR REPLACE FUNCTION public.restart_meeting(p_id BIGINT) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    -- Serialize the active-meeting check with concurrent meeting mutations.
    LOCK TABLE public.meetings IN SHARE ROW EXCLUSIVE MODE;

    IF EXISTS (
        SELECT 1 FROM public.meetings
        WHERE id <> p_id AND status IN ('running', 'paused')
    ) THEN
        RAISE EXCEPTION 'Another meeting is already running';
    END IF;

    UPDATE public.meetings
    SET status = 'upcoming',
        started_at = NULL,
        ended_at = NULL,
        paused_at = NULL,
        paused_seconds = 0,
        total_seconds = NULL
    WHERE id = p_id AND status = 'done';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Only finished meetings can be restarted';
    END IF;

    UPDATE public.meeting_schedule
    SET status = 'upcoming',
        started_at = NULL,
        ended_at = NULL,
        paused_seconds = 0,
        duration_sec = NULL
    WHERE meeting_id = p_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.restart_meeting(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.restart_meeting(BIGINT) TO authenticated;

NOTIFY pgrst, 'reload schema';
