//::///////////////////////////////////////////////
//:: mw_quiz_data -- MeaningWave guide quiz question banks.
//::
//:: GENERATED from mw_quiz_bank.yaml by bin/gen-mw-quiz.py -- DO NOT EDIT.
//:: Edit the YAML and re-run the generator (tests/check_mw_quiz.py gates it).
//::
//:: Each question is one packed row consumed by mw_quiz_inc:
//::     "QUESTION~RIGHT~WRONG1~WRONG2~WRONG3"
//:: Field 0 is the prompt, field 1 the single correct answer, 2-4 distractors.
//:://////////////////////////////////////////////

const int MW_BANK_SIZE = 20;

int MW_QCount(string sGuide) { return MW_BANK_SIZE; }

// Jocko Willink -- extreme ownership, discipline, and the laws of combat leadership
string MW_JocRow(int i)
{
    switch (i)
    {
        case 0 : return "Complete my maxim: \"Discipline equals ___.\"~Freedom.~Success.~Respect.~Strength.";
        case 1 : return "When the mission fails, whose fault is it?~Mine.~The team's.~The plan's.~Bad luck's.";
        case 2 : return "When I get bad news, what single word do I say?~\"Good.\"~\"Okay.\"~\"Understood.\"~\"Ready.\"";
        case 3 : return "The alarm goes off before dawn. What do I do?~Get up. Now.~Stretch first.~Plan the day.~Start slow.";
        case 4 : return "I do not feel like doing the work. What then?~Do it anyway.~Push through later.~Start small.~Build the habit first.";
        case 5 : return "Who owns a team's performance?~The leader.~The whole team.~Each individual.~The commander above.";
        case 6 : return "What does \"Default: Aggressive\" mean?~Attack the problem before it attacks you.~Take the fight to the enemy first.~Keep the pressure on constantly.~Meet force with greater force.";
        case 7 : return "The dichotomy of leadership means balancing traits. Which pairing is it?~Lead, but be ready to follow.~Lead hard from the front.~Trust your team completely.~Own every call yourself.";
        case 8 : return "What does \"Cover and Move\" demand?~Teams support each other toward the goal.~Advance under covering fire.~Hold position and defend.~Split up to move faster.";
        case 9 : return "How complex should a plan be?~Simple enough for anyone to execute.~Detailed enough for every case.~Flexible enough to change fast.~Clear enough for the leader.";
        case 10: return "Many problems hit at once. What do I do?~Prioritize, then execute.~Delegate across the team.~Solve the easiest first.~Attack the biggest head-on.";
        case 11: return "How do discipline and freedom relate?~Discipline creates freedom.~Freedom means doing as you please.~Talent matters more than habit.~Rest is what sets you free.";
        case 12: return "What does \"Decentralized Command\" mean?~Push decisions down to those closest to the fight.~Give clear orders from the top.~Share command among equals.~Let the team vote on calls.";
        case 13: return "In which branch did I serve?~The Navy, with the SEAL Teams.~The Army, with the Green Berets.~The Marines, with Force Recon.~The Air Force, with the Pararescuemen.";
        case 14: return "My man makes a mistake. What do I ask first?~How did I fail to lead him?~Did he understand the plan?~Was he trained enough?~What will fix it next time?";
        case 15: return "What place do excuses have?~None. Own the outcome.~A reason helps you learn.~Context explains the loss.~Some things are truly beyond us.";
        case 16: return "How should I treat a hard task?~As a chance to get better.~As a test to endure.~As a job to finish fast.~As a duty to bear.";
        case 17: return "Amid chaos, how do I see clearly?~Detach and assess the whole.~Trust your gut and move.~Focus on the nearest threat.~Fall back on the training.";
        case 18: return "Where does ownership point first?~Inward, at myself.~At the team's effort.~At the plan's flaws.~At the conditions we faced.";
        case 19: return "You feel overwhelmed. What saves you?~One priority at a time.~A short rest to reset.~Leaning on your team.~Trusting the training.";
    }
    return "";
}

// Jordan Peterson -- responsibility, hierarchy, meaning, and the order-chaos balance
string MW_PetRow(int i)
{
    switch (i)
    {
        case 0 : return "How should you carry yourself in the world?~Stand up straight, shoulders back.~Stay humble and quiet.~Blend in with the crowd.~Guard your energy.";
        case 1 : return "What is responsibility, truly?~The path to meaning, freely chosen.~A duty owed to others.~The price of freedom.~A weight we must bear.";
        case 2 : return "Whom should you measure yourself against?~Who you were yesterday.~The best in your field.~Your closest peers.~The person you hope to be.";
        case 3 : return "What dragon must you face?~The chaos within yourself.~The obstacles in your path.~The people who wrong you.~The fear of failing.";
        case 4 : return "Before you criticise the world, what must you do?~Set your own house in order.~Understand it deeply first.~Earn the right to speak.~Offer a better answer.";
        case 5 : return "What must you do, even when it costs you?~Tell the truth.~Keep your word.~Do what is right.~Stand your ground.";
        case 6 : return "What is a hierarchy of competence?~An ancient order, not a mere invention.~A ladder anyone can climb.~A useful modern tool.~A fair way to reward skill.";
        case 7 : return "You should pursue what?~What is meaningful, not expedient.~What makes you happy.~What you are good at.~What the world needs.";
        case 8 : return "I point to which creature to show hierarchy runs deep in nature?~The lobster.~The wolf.~The ape.~The bee.";
        case 9 : return "What is the antidote to resentment?~Aim up and take responsibility.~Forgive and move on.~Name what is unfair.~Count your blessings.";
        case 10: return "How should you treat yourself?~As someone you must help.~As your harshest critic.~As your own best friend.~As a work in progress.";
        case 11: return "Where is meaning found?~On the border of order and chaos.~In a life of order.~In freedom from all rules.~In serving something greater.";
        case 12: return "When you listen to someone, what should you assume?~They might know something you don't.~They mean well.~They see it their own way.~They want to be heard.";
        case 13: return "What befalls a person who abandons truth?~He descends into his own hell.~He loses others' trust.~He forgets who he is.~He weakens over time.";
        case 14: return "In what must you be precise?~Your speech.~Your aim.~Your habits.~Your promises.";
        case 15: return "Where does order begin?~With the small things you can fix now.~With a clear plan.~With honest self-reflection.~With the right values.";
        case 16: return "What is the tragedy of Being?~Suffering is woven in, yet can be borne.~Suffering falls only on the unlucky.~Enough progress will end it.~Meaning removes all pain.";
        case 17: return "What kind of friends should you make?~Those who want the best for you.~Those who are fun to be with.~Those who challenge you.~Those loyal no matter what.";
        case 18: return "What two forces must you balance?~Order and chaos.~Reason and emotion.~Freedom and duty.~Self and others.";
        case 19: return "Why measure yourself only against your past self?~To escape envy and false comparison.~To track real progress.~To stay humble.~To set fair goals.";
    }
    return "";
}

// Alan Watts -- ego, nonduality, flow, and the universe at play
string MW_WatRow(int i)
{
    switch (i)
    {
        case 0 : return "Who is doing the experiencing?~No separate self apart from the experience.~The mind behind your eyes.~The soul within the body.~The 'I' that watches it all.";
        case 1 : return "What is the great secret you were never told?~You are the whole universe, not a separate ego.~Your fate is already written.~Desire is the root of suffering.~The world is a passing dream.";
        case 2 : return "What is the universe, really?~A cosmic game of hide-and-seek.~A grand design with a purpose.~A vast, living organism.~A mystery beyond knowing.";
        case 3 : return "Why act at all, if the goal is incidental?~Because the doing is the play.~Because growth is the point.~Because the world needs you.~Because effort is its own reward.";
        case 4 : return "The self is more like which part of speech?~A verb, not a noun.~A noun, solid and real.~A story we tell.~A name we answer to.";
        case 5 : return "How do you truly let go?~By yielding, not gripping harder.~By understanding its cause.~By replacing it with something better.~By simply deciding to.";
        case 6 : return "Where is real security found?~In accepting that all things pass.~In building something lasting.~In faith and trust.~In knowing yourself well.";
        case 7 : return "Which two ways of seeing do I draw from most?~Zen and the Tao.~Stoicism and Zen.~Hinduism and Sufism.~Buddhism and Christianity.";
        case 8 : return "What is \"wu wei\"?~Effortless action, with the grain of things.~Patient, steady effort.~Action guided by reason.~Stillness and quiet.";
        case 9 : return "What is the ego, really?~A useful illusion, a social mask.~The core of who you are.~The voice of conscience.~The seat of the will.";
        case 10: return "Chase pleasure head-on, and what happens?~It slips through your fingers.~It leaves you wanting more.~It costs more than it gives.~It dulls over time.";
        case 11: return "Believing you are a lone ego in a bag of skin is what?~A hallucination of separateness.~Simple common sense.~The way we are built to feel.~A hard truth to accept.";
        case 12: return "What is \"satori\"?~A sudden flash of awakening.~A lifetime of practice.~A deep, calm peace.~A state of pure focus.";
        case 13: return "Life is like music. Why?~The point is the playing, not the end.~Every part has its rhythm.~It rises and falls in time.~It moves us beyond words.";
        case 14: return "What do yin and yang teach?~Opposites need each other.~Balance is the goal.~All things are in flux.~Light will outlast the dark.";
        case 15: return "What are you, at the deepest level?~The universe knowing itself.~A spark of the divine.~A mind made of matter.~A soul on a journey.";
        case 16: return "\"You are the universe experiencing itself\" points to what?~Nonduality: self and cosmos are one.~Pantheism: God is all things.~Idealism: all is mind.~Humanism: we make our own meaning.";
        case 17: return "What of the present moment?~It is the only place life happens.~It shapes the future.~It passes too quickly to hold.~It is best not to dwell in.";
        case 18: return "How does the sage meet nature?~Flowing with it, not forcing it.~Studying its every law.~Living simply within it.~Tending it with care.";
        case 19: return "What is the cosmos, in a word?~Playful and all connected.~Vast and mysterious.~Ordered and lawful.~Sacred and alive.";
    }
    return "";
}

// Joseph Campbell -- the monomyth: departure, initiation, and the return
string MW_CamRow(int i)
{
    switch (i)
    {
        case 0 : return "What begins every hero's journey?~The Call to Adventure.~A great loss.~A chance meeting.~A restless longing.";
        case 1 : return "What does the threshold guardian do?~Tests whether you are worthy to cross.~Warns of the dangers ahead.~Demands a price to pass.~Points the hero's way.";
        case 2 : return "Why must the hero descend into the dark?~To die to the old self and be reborn.~To find a hidden strength.~To face his deepest fear.~To win the great prize.";
        case 3 : return "What single counsel do I give for a life?~Follow your bliss.~Know thyself.~Serve a cause.~Seek the truth.";
        case 4 : return "What do I call the one myth beneath all cultures?~The monomyth.~The archetype.~The great story.~The eternal return.";
        case 5 : return "The hero's journey is ultimately a figure for what?~Inner transformation.~The path to power.~The search for home.~The triumph of good.";
        case 6 : return "To cross the first threshold means what?~Leaving the ordinary world behind.~Passing the first test.~Making the fateful choice.~Facing the unknown at last.";
        case 7 : return "The one who gives supernatural aid is usually what?~A mentor or wise guide.~A loyal companion.~A hidden god.~A former hero.";
        case 8 : return "What is the \"Refusal of the Call\"?~The hero's first hesitation.~The villain's challenge.~A test of resolve.~The turning point.";
        case 9 : return "The three phases of the hero's journey are Departure, Initiation, and what?~Return.~Trial.~Reward.~Renewal.";
        case 10: return "What does the \"belly of the whale\" mark?~The passage into transformation.~The point of no return.~The darkest despair.~A time of hidden rest.";
        case 11: return "What do myths do for us?~Give life meaning and shape the soul.~Preserve a people's past.~Teach right from wrong.~Explain the mysteries of nature.";
        case 12: return "What ordeal awaits at the darkest point?~The supreme trial.~The final reward.~The long road home.~The mentor's parting.";
        case 13: return "\"Meeting the goddess\" and \"atonement with the father\" belong to which phase?~Initiation.~Departure.~Return.~The Call.";
        case 14: return "Where does the hero's road begin?~In the ordinary, everyday world.~At a moment of crisis.~In a place of safety.~At the edge of the unknown.";
        case 15: return "What does \"follow your bliss\" truly mean?~Pursue your deepest calling, whatever it costs.~Do what brings you joy.~Trust where life leads you.~Find work you love.";
        case 16: return "Whom does the hero's journey ultimately serve?~The community he returns to.~The hero's own growth.~The generations to come.~The gods who sent him.";
        case 17: return "What is the \"ultimate boon\"?~The prize that can renew the world.~The wisdom hard-won.~The treasure long sought.~The hero's true name.";
        case 18: return "What befalls the hero who refuses to return?~His gift is lost to the world.~He remains forever changed.~He must begin again.~He finds peace apart.";
        case 19: return "What does the hero carry home?~A boon for his people.~The scars of his trials.~A story worth telling.~Wisdom he cannot share.";
    }
    return "";
}

// Terence McKenna -- culture, novelty, the Other, and direct experience
string MW_MckRow(int i)
{
    switch (i)
    {
        case 0 : return "What is culture, really?~Your operating system.~A shared way of life.~The story a people tells.~A set of inherited rules.";
        case 1 : return "Complete my phrase: \"the felt presence of ___.\"~immediate experience.~the living cosmos.~the eternal now.~another mind.";
        case 2 : return "What is the timewave?~A fractal of rising novelty.~A cycle of endless return.~A map of history's turns.~A rhythm of the cosmos.";
        case 3 : return "How near is \"the Other\"?~Closer than your own breath.~Just beyond ordinary sight.~Deep within the mind.~At the edge of the cosmos.";
        case 4 : return "What is language, to me?~A living thing that longs to be shared.~A tool for shaping thought.~A bridge between minds.~A gift we are born to use.";
        case 5 : return "What sparked the leap in the human mind?~Psilocybin in the primate diet.~The mastery of fire.~The dawn of language.~The making of tools.";
        case 6 : return "What is the mushroom, to me?~A teacher, not a drug.~A door to other worlds.~A gift from the earth.~A medicine for the mind.";
        case 7 : return "What \"return\" did I call for?~A return to shamanic ways.~A return to nature.~A return to wonder.~A return to the body.";
        case 8 : return "What is \"novelty\"?~Rising complexity and connection.~The birth of new ideas.~The thrill of the unknown.~A break from routine.";
        case 9 : return "What waits at the end of time?~An attractor drawing all novelty on.~A great awakening.~A merging of all minds.~A door beyond time.";
        case 10: return "What is \"boundary dissolution\"?~Self and world melting into one.~The mind opening wide.~A release from all fear.~The fading of the ego.";
        case 11: return "What is the \"syntactic prison\"?~Being trapped inside habitual language.~The limits of the thinking mind.~The rules society imposes.~The cage of old beliefs.";
        case 12: return "What is the imagination, to me?~A real ground of being to explore.~The source of all creation.~A window to the soul.~The mind's deepest power.";
        case 13: return "What does the psychedelic doorway open?~A path to meaning and mind.~A glimpse of the divine.~The doors of perception.~A journey within.";
        case 14: return "What should you trust above dogma?~Your own direct experience.~The wisdom of nature.~An open, questioning mind.~The evidence of your senses.";
        case 15: return "Who are the truest teachers?~The plants and the living world.~The old shamans and sages.~Your own inner voice.~The great mystics of history.";
        case 16: return "How should you treat any one guru?~Follow none of them blindly.~Learn what you can, then move on.~Question all they teach.~Trust only what you test.";
        case 17: return "What did I feel about the future?~A shift in consciousness is coming.~A great transformation awaits.~Wonders we cannot yet imagine.~A return to older wisdom.";
        case 18: return "What is a \"heroic dose\"?~A big dose, taken in silent dark.~A dose taken with a guide.~The largest one can bear.~A dose for deep questions.";
        case 19: return "\"Culture is not your friend\" warns you to do what?~Not let culture define you.~Question what you were taught.~Think for yourself.~See past its illusions.";
    }
    return "";
}

// Carl Jung -- the shadow, individuation, persona, and the archetypes
string MW_JunRow(int i)
{
    switch (i)
    {
        case 0 : return "What is the shadow?~The disowned parts of yourself.~The dark side of the mind.~The self you hide from others.~The instincts we repress.";
        case 1 : return "How do you become whole?~By integrating the shadow.~By mastering your instincts.~By rising above the ego.~By healing old wounds.";
        case 2 : return "What is individuation?~Becoming all of who you are.~Standing apart from the crowd.~Finding your true purpose.~Making peace with the past.";
        case 3 : return "What fills the collective unconscious?~Shared archetypes of all humankind.~Memories from this life alone.~Instincts passed from your parents.~Urges left over from childhood.";
        case 4 : return "What is the persona?~The mask you wear for the world.~The role you play in life.~The face you show at work.~The self you present to others.";
        case 5 : return "What do I call the deep images shared by us all?~Archetypes.~Symbols.~Instincts.~Myths.";
        case 6 : return "What is the \"anima\"?~The inner feminine in a man.~The soul's true voice.~A guide met in dreams.~The gentler side of the self.";
        case 7 : return "What do I call a meaningful coincidence?~Synchronicity.~Fate.~Providence.~Intuition.";
        case 8 : return "What does it mean to hold the tension of opposites?~Bear both sides until they unite.~Choose the wiser path.~Find the middle way.~Let time resolve it.";
        case 9 : return "What is the \"Self\", with a capital S?~The whole psyche's uniting centre.~The soul within us all.~The person we truly are.~The image of God within.";
        case 10: return "What becomes of a shadow left unowned?~It is cast onto others.~It grows in the dark.~It surfaces in dreams.~It rules from behind.";
        case 11: return "The persona is useful, but what is its danger?~Mistaking the mask for your true self.~Wearing it too often.~Losing touch with others.~Hiding your real gifts.";
        case 12: return "What do dreams do, in my view?~Speak and balance from the unconscious.~Reveal our hidden wishes.~Work through the day's cares.~Warn us of what may come.";
        case 13: return "The \"wise old man\" and \"great mother\" are what?~Archetypes.~Symbols.~Spirits.~Instincts.";
        case 14: return "What is a \"complex\"?~A charged knot of feelings and ideas.~A deep-seated fear.~A pattern of behaviour.~A wound from the past.";
        case 15: return "What should the second half of life turn toward?~Meaning and the inner world.~Passing on what you have learned.~Making peace with the end.~Deepening your closest bonds.";
        case 16: return "What is the \"animus\"?~The inner masculine in a woman.~The strength within the self.~A figure seen in dreams.~The voice of reason inside.";
        case 17: return "How do I see religious symbols?~As voices of deep psychic truth.~As maps of the inner life.~As humanity's oldest wisdom.~As bridges to the sacred.";
        case 18: return "How does facing your shadow feel at first?~Uneasy, even shameful.~Strange and unfamiliar.~Frightening yet freeing.~Humbling but honest.";
        case 19: return "What is the aim of the whole work?~Wholeness of the psyche.~Peace of mind.~Self-knowledge.~Freedom from the past.";
    }
    return "";
}

// Marcus Aurelius -- the dichotomy of control, virtue, and memento mori
string MW_AurRow(int i)
{
    switch (i)
    {
        case 0 : return "What is truly in your power?~Your judgements and reactions.~Your words and deeds.~Your effort and will.~Your duty to others.";
        case 1 : return "Complete the maxim: \"The obstacle is ___.\"~the way.~a teacher.~a test.~temporary.";
        case 2 : return "What does \"memento mori\" mean?~Remember that you will die.~Live each day fully.~Honour those now gone.~Time is always fleeting.";
        case 3 : return "By what is the soul dyed?~The colour of its thoughts.~The company it keeps.~The deeds it does.~The trials it endures.";
        case 4 : return "How should you begin each day?~Braced to meet difficult people, unshaken.~Grateful to be alive.~Set on your duties.~Calm and clear of mind.";
        case 5 : return "Into which two kinds do I sort all things?~What is up to us, and what is not.~The good and the harmful.~The lasting and the fleeting.~The body and the mind.";
        case 6 : return "What alone is truly good?~A virtuous character.~A tranquil mind.~A life well lived.~Wisdom hard-won.";
        case 7 : return "When wronged, how do you answer?~Return to reason, not revenge.~Forgive and let it go.~Set a firm boundary.~Consider their reasons.";
        case 8 : return "Complete the thought: \"The best revenge is ___.\"~to be unlike your enemy.~to rise above it.~to live well.~to feel no anger.";
        case 9 : return "What of things beyond your control?~Accept them with calm.~Prepare for them wisely.~Trust they serve a purpose.~Turn your mind elsewhere.";
        case 10: return "What should you recall about all things?~They pass and are soon forgotten.~They change without cease.~They serve the whole.~They are as nature wills.";
        case 11: return "What does \"amor fati\" mean?~Love of your own fate.~Trust in providence.~Peace with what is.~Courage before death.";
        case 12: return "What should you do instead of complaining?~The work in front of you.~Give quiet thanks.~Accept what is.~Look for the lesson.";
        case 13: return "What should reason, the ruling part, govern?~Your impulses and reactions.~Your daily choices.~Your desires and fears.~Your whole way of life.";
        case 14: return "How do I picture the cosmos?~One ordered, connected whole.~A living, breathing being.~A work of divine reason.~A dance of endless change.";
        case 15: return "How does the sage stand amid change?~Tranquil and steadfast.~Watchful and ready.~Humble and accepting.~Patient and wise.";
        case 16: return "For whose good should you act?~The good of the whole.~The good of your city.~Those in your care.~Future generations.";
        case 17: return "How should you regard death?~As natural, nothing to fear.~As a return to nature.~As the door to rest.~As the price of life.";
        case 18: return "What, in truth, can harm you?~Your own judgement of events.~A life without virtue.~The loss of reason.~Turning from duty.";
        case 19: return "Where should your attention rest?~On the task before you now.~On living by virtue.~On the good of others.~On what you can control.";
    }
    return "";
}

// Dispatch: packed row for guide sGuide, question index i (0-based).
string MW_QRow(string sGuide, int i)
{
    if (sGuide == "jocko")     return MW_JocRow(i);
    if (sGuide == "peterson")  return MW_PetRow(i);
    if (sGuide == "watts")     return MW_WatRow(i);
    if (sGuide == "campbell")  return MW_CamRow(i);
    if (sGuide == "mckenna")   return MW_MckRow(i);
    if (sGuide == "jung")      return MW_JunRow(i);
    if (sGuide == "aurelius")  return MW_AurRow(i);
    return "";
}
