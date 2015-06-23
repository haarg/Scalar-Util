/* Copyright (c) 1997-2000 Graham Barr <gbarr@pobox.com>. All rights reserved.
 * This program is free software; you can redistribute it and/or
 * modify it under the same terms as Perl itself.
 */
#define PERL_NO_GET_CONTEXT /* we want efficiency */
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#define NEED_sv_2pv_flags 1
#include "ppport.h"

#ifndef CvISXSUB
#  define CvISXSUB(cv) CvXSUB(cv)
#endif

/* Some platforms have strict exports. And before 5.7.3 cxinc (or Perl_cxinc)
   was not exported. Therefore platforms like win32, VMS etc have problems
   so we redefine it here -- GMB
*/
#if PERL_BCDVERSION < 0x5007000
/* Not in 5.6.1. */
#  ifdef cxinc
#    undef cxinc
#  endif
#  define cxinc() my_cxinc(aTHX)
static I32
my_cxinc(pTHX)
{
    cxstack_max = cxstack_max * 3 / 2;
    Renew(cxstack, cxstack_max + 1, struct context); /* fencepost bug in older CXINC macros requires +1 here */
    return cxstack_ix + 1;
}
#endif

#ifndef sv_copypv
#define sv_copypv(a, b) my_sv_copypv(aTHX_ a, b)
static void
my_sv_copypv(pTHX_ SV *const dsv, SV *const ssv)
{
    STRLEN len;
    const char * const s = SvPV_const(ssv,len);
    sv_setpvn(dsv,s,len);
    if(SvUTF8(ssv))
        SvUTF8_on(dsv);
    else
        SvUTF8_off(dsv);
}
#endif

#ifdef SVf_IVisUV
#  define slu_sv_value(sv) (SvIOK(sv)) ? (SvIOK_UV(sv)) ? (NV)(SvUVX(sv)) : (NV)(SvIVX(sv)) : (SvNV(sv))
#else
#  define slu_sv_value(sv) (SvIOK(sv)) ? (NV)(SvIVX(sv)) : (SvNV(sv))
#endif

#if PERL_VERSION < 14
#  define croak_no_modify() croak("%s", PL_no_modify)
#endif

enum slu_accum {
    ACC_IV,
    ACC_NV,
    ACC_SV,
};

static enum slu_accum accum_type(SV *sv) {
    if(SvAMAGIC(sv))
        return ACC_SV;

    if(SvIOK(sv) && !SvNOK(sv) && !SvUOK(sv))
        return ACC_IV;

    return ACC_NV;
}

/* Magic for set_subname */
static MGVTBL subname_vtbl;

MODULE=Scalar::Util       PACKAGE=Scalar::Util

void
dualvar(num,str)
    SV *num
    SV *str
PROTOTYPE: $$
CODE:
{
    dXSTARG;

    (void)SvUPGRADE(TARG, SVt_PVNV);

    sv_copypv(TARG,str);

    if(SvNOK(num) || SvPOK(num) || SvMAGICAL(num)) {
        SvNV_set(TARG, SvNV(num));
        SvNOK_on(TARG);
    }
#ifdef SVf_IVisUV
    else if(SvUOK(num)) {
        SvUV_set(TARG, SvUV(num));
        SvIOK_on(TARG);
        SvIsUV_on(TARG);
    }
#endif
    else {
        SvIV_set(TARG, SvIV(num));
        SvIOK_on(TARG);
    }

    if(PL_tainting && (SvTAINTED(num) || SvTAINTED(str)))
        SvTAINTED_on(TARG);

    ST(0) = TARG;
    XSRETURN(1);
}

void
isdual(sv)
    SV *sv
PROTOTYPE: $
CODE:
    if(SvMAGICAL(sv))
        mg_get(sv);

    ST(0) = boolSV((SvPOK(sv) || SvPOKp(sv)) && (SvNIOK(sv) || SvNIOKp(sv)));
    XSRETURN(1);

char *
blessed(sv)
    SV *sv
PROTOTYPE: $
CODE:
{
    SvGETMAGIC(sv);

    if(!(SvROK(sv) && SvOBJECT(SvRV(sv))))
        XSRETURN_UNDEF;

    RETVAL = (char*)sv_reftype(SvRV(sv),TRUE);
}
OUTPUT:
    RETVAL

char *
reftype(sv)
    SV *sv
PROTOTYPE: $
CODE:
{
    SvGETMAGIC(sv);
    if(!SvROK(sv))
        XSRETURN_UNDEF;

    RETVAL = (char*)sv_reftype(SvRV(sv),FALSE);
}
OUTPUT:
    RETVAL

UV
refaddr(sv)
    SV *sv
PROTOTYPE: $
CODE:
{
    SvGETMAGIC(sv);
    if(!SvROK(sv))
        XSRETURN_UNDEF;

    RETVAL = PTR2UV(SvRV(sv));
}
OUTPUT:
    RETVAL

void
weaken(sv)
    SV *sv
PROTOTYPE: $
CODE:
#ifdef SvWEAKREF
    sv_rvweaken(sv);
#else
    croak("weak references are not implemented in this release of perl");
#endif

void
unweaken(sv)
    SV *sv
PROTOTYPE: $
INIT:
    SV *tsv;
CODE:
#ifdef SvWEAKREF
    /* This code stolen from core's sv_rvweaken() and modified */
    if (!SvOK(sv))
        return;
    if (!SvROK(sv))
        croak("Can't unweaken a nonreference");
    else if (!SvWEAKREF(sv)) {
        if(ckWARN(WARN_MISC))
            warn("Reference is not weak");
        return;
    }
    else if (SvREADONLY(sv)) croak_no_modify();

    tsv = SvRV(sv);
#if PERL_VERSION >= 14
    SvWEAKREF_off(sv); SvROK_on(sv);
    SvREFCNT_inc_NN(tsv);
    Perl_sv_del_backref(aTHX_ tsv, sv);
#else
    /* Lacking sv_del_backref() the best we can do is clear the old (weak) ref
     * then set a new strong one
     */
    sv_setsv(sv, &PL_sv_undef);
    SvRV_set(sv, SvREFCNT_inc_NN(tsv));
    SvROK_on(sv);
#endif
#else
    croak("weak references are not implemented in this release of perl");
#endif

void
isweak(sv)
    SV *sv
PROTOTYPE: $
CODE:
#ifdef SvWEAKREF
    ST(0) = boolSV(SvROK(sv) && SvWEAKREF(sv));
    XSRETURN(1);
#else
    croak("weak references are not implemented in this release of perl");
#endif

int
readonly(sv)
    SV *sv
PROTOTYPE: $
CODE:
    SvGETMAGIC(sv);
    RETVAL = SvREADONLY(sv);
OUTPUT:
    RETVAL

int
tainted(sv)
    SV *sv
PROTOTYPE: $
CODE:
    SvGETMAGIC(sv);
    RETVAL = SvTAINTED(sv);
OUTPUT:
    RETVAL

void
isvstring(sv)
    SV *sv
PROTOTYPE: $
CODE:
#ifdef SvVOK
    SvGETMAGIC(sv);
    ST(0) = boolSV(SvVOK(sv));
    XSRETURN(1);
#else
    croak("vstrings are not implemented in this release of perl");
#endif

SV *
looks_like_number(sv)
    SV *sv
PROTOTYPE: $
CODE:
    SV *tempsv;
    SvGETMAGIC(sv);
    if(SvAMAGIC(sv) && (tempsv = AMG_CALLun(sv, numer))) {
        sv = tempsv;
    }
#if PERL_BCDVERSION < 0x5008005
    if(SvPOK(sv) || SvPOKp(sv)) {
        RETVAL = looks_like_number(sv) ? &PL_sv_yes : &PL_sv_no;
    }
    else {
        RETVAL = (SvFLAGS(sv) & (SVf_NOK|SVp_NOK|SVf_IOK|SVp_IOK)) ? &PL_sv_yes : &PL_sv_no;
    }
#else
    RETVAL = looks_like_number(sv) ? &PL_sv_yes : &PL_sv_no;
#endif
OUTPUT:
    RETVAL

void
openhandle(SV *sv)
PROTOTYPE: $
CODE:
{
    IO *io = NULL;
    SvGETMAGIC(sv);
    if(SvROK(sv)){
        /* deref first */
        sv = SvRV(sv);
    }

    /* must be GLOB or IO */
    if(isGV(sv)){
        io = GvIO((GV*)sv);
    }
    else if(SvTYPE(sv) == SVt_PVIO){
        io = (IO*)sv;
    }

    if(io){
        /* real or tied filehandle? */
        if(IoIFP(io) || SvTIED_mg((SV*)io, PERL_MAGIC_tiedscalar)){
            XSRETURN(1);
        }
    }
    XSRETURN_UNDEF;
}

MODULE=Scalar::Util       PACKAGE=Sub::Util

void
set_prototype(proto, code)
    SV *proto
    SV *code
PREINIT:
    SV *cv; /* not CV * */
PPCODE:
    SvGETMAGIC(code);
    if(!SvROK(code))
        croak("set_prototype: not a reference");

    cv = SvRV(code);
    if(SvTYPE(cv) != SVt_PVCV)
        croak("set_prototype: not a subroutine reference");

    if(SvPOK(proto)) {
        /* set the prototype */
        sv_copypv(cv, proto);
    }
    else {
        /* delete the prototype */
        SvPOK_off(cv);
    }

    PUSHs(code);
    XSRETURN(1);

void
set_subname(name, sub)
    char *name
    SV *sub
PREINIT:
    CV *cv = NULL;
    GV *gv;
    HV *stash = CopSTASH(PL_curcop);
    char *s, *end = NULL;
    MAGIC *mg;
PPCODE:
    if (!SvROK(sub) && SvGMAGICAL(sub))
        mg_get(sub);
    if (SvROK(sub))
        cv = (CV *) SvRV(sub);
    else if (SvTYPE(sub) == SVt_PVGV)
        cv = GvCVu(sub);
    else if (!SvOK(sub))
        croak(PL_no_usym, "a subroutine");
    else if (PL_op->op_private & HINT_STRICT_REFS)
        croak("Can't use string (\"%.32s\") as %s ref while \"strict refs\" in use",
              SvPV_nolen(sub), "a subroutine");
    else if ((gv = gv_fetchpv(SvPV_nolen(sub), FALSE, SVt_PVCV)))
        cv = GvCVu(gv);
    if (!cv)
        croak("Undefined subroutine %s", SvPV_nolen(sub));
    if (SvTYPE(cv) != SVt_PVCV && SvTYPE(cv) != SVt_PVFM)
        croak("Not a subroutine reference");
    for (s = name; *s++; ) {
        if (*s == ':' && s[-1] == ':')
            end = ++s;
        else if (*s && s[-1] == '\'')
            end = s;
    }
    s--;
    if (end) {
        char *namepv = savepvn(name, end - name);
        stash = GvHV(gv_fetchpv(namepv, TRUE, SVt_PVHV));
        Safefree(namepv);
        name = end;
    }

    /* under debugger, provide information about sub location */
    if (PL_DBsub && CvGV(cv)) {
        HV *hv = GvHV(PL_DBsub);

        char *new_pkg = HvNAME(stash);

        char *old_name = GvNAME( CvGV(cv) );
        char *old_pkg = HvNAME( GvSTASH(CvGV(cv)) );

        int old_len = strlen(old_name) + strlen(old_pkg);
        int new_len = strlen(name) + strlen(new_pkg);

        SV **old_data;
        char *full_name;

        Newxz(full_name, (old_len > new_len ? old_len : new_len) + 3, char);

        strcat(full_name, old_pkg);
        strcat(full_name, "::");
        strcat(full_name, old_name);

        old_data = hv_fetch(hv, full_name, strlen(full_name), 0);

        if (old_data) {
            strcpy(full_name, new_pkg);
            strcat(full_name, "::");
            strcat(full_name, name);

            SvREFCNT_inc(*old_data);
            if (!hv_store(hv, full_name, strlen(full_name), *old_data, 0))
                SvREFCNT_dec(*old_data);
        }
        Safefree(full_name);
    }

    gv = (GV *) newSV(0);
    gv_init(gv, stash, name, s - name, TRUE);

    /*
     * set_subname needs to create a GV to store the name. The CvGV field of a
     * CV is not refcounted, so perl wouldn't know to SvREFCNT_dec() this GV if
     * it destroys the containing CV. We use a MAGIC with an empty vtable
     * simply for the side-effect of using MGf_REFCOUNTED to store the
     * actually-counted reference to the GV.
     */
    mg = SvMAGIC(cv);
    while (mg && mg->mg_virtual != &subname_vtbl)
        mg = mg->mg_moremagic;
    if (!mg) {
        Newxz(mg, 1, MAGIC);
        mg->mg_moremagic = SvMAGIC(cv);
        mg->mg_type = PERL_MAGIC_ext;
        mg->mg_virtual = &subname_vtbl;
        SvMAGIC_set(cv, mg);
    }
    if (mg->mg_flags & MGf_REFCOUNTED)
        SvREFCNT_dec(mg->mg_obj);
    mg->mg_flags |= MGf_REFCOUNTED;
    mg->mg_obj = (SV *) gv;
    SvRMAGICAL_on(cv);
    CvANON_off(cv);
#ifndef CvGV_set
    CvGV(cv) = gv;
#else
    CvGV_set(cv, gv);
#endif
    PUSHs(sub);

void
subname(code)
    SV *code
PREINIT:
    CV *cv;
    GV *gv;
PPCODE:
    if (!SvROK(code) && SvGMAGICAL(code))
        mg_get(code);

    if(!SvROK(code) || SvTYPE(cv = (CV *)SvRV(code)) != SVt_PVCV)
        croak("Not a subroutine reference");

    if(!(gv = CvGV(cv)))
        XSRETURN(0);

    mPUSHs(newSVpvf("%s::%s", HvNAME(GvSTASH(gv)), GvNAME(gv)));
    XSRETURN(1);

BOOT:
{
#if !defined(SvWEAKREF) || !defined(SvVOK)
    HV *su_stash = gv_stashpvn("Scalar::Util", 12, TRUE);
    GV *vargv = *(GV**)hv_fetch(su_stash, "EXPORT_FAIL", 11, TRUE);
    AV *varav;
    if(SvTYPE(vargv) != SVt_PVGV)
        gv_init(vargv, su_stash, "Scalar::Util", 12, TRUE);
    varav = GvAVn(vargv);
#endif
#ifndef SvWEAKREF
    av_push(varav, newSVpv("weaken",6));
    av_push(varav, newSVpv("isweak",6));
#endif
#ifndef SvVOK
    av_push(varav, newSVpv("isvstring",9));
#endif
}
