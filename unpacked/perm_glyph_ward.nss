void main()
{

if(GetLocalInt(OBJECT_SELF, "glyph")!=1)
{
SetLocalInt(OBJECT_SELF, "glyph", 1);

// show glyph symbol only for 6 seconds
ApplyEffectToObject(DURATION_TYPE_PERMANENT,EffectVisualEffect(445),OBJECT_SELF, 0.0f);

}


}
