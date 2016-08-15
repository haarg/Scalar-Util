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

#if PERL_BCDVERSION >= 0x5006000
#  include "multicall.h"
#endif

#if PERL_BCDVERSION < 0x5023008
#  define UNUSED_VAR_newsp PERL_UNUSED_VAR(newsp)
#else
#  define UNUSED_VAR_newsp NOOP
#endif

#ifndef CvISXSUB
#  define CvISXSUB(cv) CvXSUB(cv)
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

#if PERL_VERSION < 14
#  define croak_no_modify() croak("%s", PL_no_modify)
#endif

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

void
set_prototype(code, proto)
     SV *code
     SV *proto
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
