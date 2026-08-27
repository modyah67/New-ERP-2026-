-- Add treasury_id to cheques table to link cheques directly to a treasury
ALTER TABLE public.cheques 
ADD COLUMN IF NOT EXISTS treasury_id BIGINT REFERENCES public.treasuries(id) ON DELETE SET NULL;

-- Reload PostgREST schema cache so the API recognizes the new column
NOTIFY pgrst, 'reload schema';
