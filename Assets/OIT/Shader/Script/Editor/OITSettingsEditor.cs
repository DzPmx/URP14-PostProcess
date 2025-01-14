using OIT;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

[CustomEditor(typeof(OITSettings))]
public class OITSettingsEditor : Editor
{
    private OITSettings oitSettings;

    public override void OnInspectorGUI()
    {
        oitSettings = (OITSettings)target;
        oitSettings.oitMode = (OITMode)EditorGUILayout.EnumPopup("OIT Mode", oitSettings.oitMode);
        oitSettings.cullMode = (CullMode)EditorGUILayout.EnumPopup("Cull Mode", oitSettings.cullMode);
        switch (oitSettings.oitMode)
        {
            case OITMode.DepthPeeling:
                DPGUI();
                break;
            case OITMode.WeightedBlend:
                WBGUI();
                break;
            case OITMode.PerpiexlLinkedList:
                PPLL();
                break;
            case OITMode.PreviewAll:
                DPGUI();
                WBGUI();
                PPLL();
                break;
        }

        serializedObject.ApplyModifiedProperties();
    }

    public void DPGUI()
    {
        EditorGUILayout.LabelField("Depth Peeling OIT", EditorStyles.boldLabel);
        oitSettings.layers = (int)EditorGUILayout.Slider("Depth Peeling Layers", oitSettings.layers, 1, 6);
        oitSettings.DP_initialShader = (Shader)
            EditorGUILayout.ObjectField("DP Initial Shader", oitSettings.DP_initialShader, typeof(Shader), false);
        oitSettings.DP_depthPeelingShader = (Shader)
            EditorGUILayout.ObjectField("DP Depth Peeling Shader", oitSettings.DP_depthPeelingShader, typeof(Shader),
                false);
        oitSettings.DP_blendShader = (Shader)
            EditorGUILayout.ObjectField("DP Blend Shader", oitSettings.DP_blendShader, typeof(Shader), false);
    }

    public void WBGUI()
    {
        EditorGUILayout.LabelField("Weighted Blend OIT", EditorStyles.boldLabel);
        oitSettings.WeightFunction =
            (WeightFunction)EditorGUILayout.EnumPopup("Weight Function", oitSettings.WeightFunction);
        oitSettings.WB_accumulateShader = (Shader)
            EditorGUILayout.ObjectField("WB Accumulate Shader", oitSettings.WB_accumulateShader, typeof(Shader), false);
        oitSettings.WB_revealageShader = (Shader)
            EditorGUILayout.ObjectField("WB Revealage Shader", oitSettings.WB_revealageShader, typeof(Shader),
                false);
        oitSettings.WB_blendShader = (Shader)
            EditorGUILayout.ObjectField("WB Blend Shader", oitSettings.WB_blendShader, typeof(Shader), false);
    }

    public void PPLL()
    {
        EditorGUILayout.LabelField("Perpixel Linked List OIT", EditorStyles.boldLabel);
        oitSettings.PPLL_InitialShader = (Shader)
            EditorGUILayout.ObjectField("PPLL Initial Shader", oitSettings.PPLL_InitialShader, typeof(Shader), false);
        oitSettings.PPLL_BlendShader = (Shader)
            EditorGUILayout.ObjectField("PPLL Blend Shader", oitSettings.PPLL_BlendShader, typeof(Shader),
                false);
    }
}