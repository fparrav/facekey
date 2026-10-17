/*
 * pam_spike — minimal PAM module for the /usr/bin/sudo loading spike.
 * Logs one line per authenticate() call; never influences the result.
 */

#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
	(void)pamh; (void)flags; (void)argc; (void)argv;
	FILE *log = fopen("/tmp/facekey-pam-spike.log", "a");
	if (log != NULL) {
		fprintf(log, "pam_spike authenticate pid=%d time=%ld\n",
		    getpid(), (long)time(NULL));
		fclose(log);
	}
	/* Spike module must never alter the auth decision. */
	return (PAM_IGNORE);
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv)
{ (void)pamh; (void)flags; (void)argc; (void)argv; return (PAM_IGNORE); }

PAM_EXTERN int pam_sm_acct_mgmt(pam_handle_t *pamh, int flags, int argc, const char **argv)
{ (void)pamh; (void)flags; (void)argc; (void)argv; return (PAM_IGNORE); }

PAM_EXTERN int pam_sm_chauthtok(pam_handle_t *pamh, int flags, int argc, const char **argv)
{ (void)pamh; (void)flags; (void)argc; (void)argv; return (PAM_IGNORE); }

PAM_EXTERN int pam_sm_open_session(pam_handle_t *pamh, int flags, int argc, const char **argv)
{ (void)pamh; (void)flags; (void)argc; (void)argv; return (PAM_IGNORE); }

PAM_EXTERN int pam_sm_close_session(pam_handle_t *pamh, int flags, int argc, const char **argv)
{ (void)pamh; (void)flags; (void)argc; (void)argv; return (PAM_IGNORE); }
